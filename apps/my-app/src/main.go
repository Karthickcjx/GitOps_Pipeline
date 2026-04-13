// =============================================================================
// my-app — Main Application
// =============================================================================
// A production-ready Go microservice with:
//   - HTTP server with graceful shutdown
//   - Health check endpoints (/healthz, /ready)
//   - Prometheus metrics endpoint (/metrics)
//   - Structured JSON logging
//   - Signal handling for SIGTERM/SIGINT
// =============================================================================

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Build-time variables (set via -ldflags)
var (
	version   = "dev"
	commit    = "unknown"
	buildTime = "unknown"
)

// Application state
var (
	ready   int32 = 0
	healthy int32 = 1
)

// Prometheus metrics
var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "path", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "path"},
	)

	appInfo = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "app_info",
			Help: "Application build information",
		},
		[]string{"version", "commit", "go_version"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
	prometheus.MustRegister(appInfo)

	appInfo.WithLabelValues(version, commit, runtime.Version()).Set(1)
}

// metricsMiddleware wraps handlers with Prometheus instrumentation
func metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		wrapped := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}

		next.ServeHTTP(wrapped, r)

		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", wrapped.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.statusCode = code
	r.ResponseWriter.WriteHeader(code)
}

func main() {
	// Structured JSON logger
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	slog.Info("Starting application",
		"version", version,
		"commit", commit,
		"build_time", buildTime,
		"go_version", runtime.Version(),
	)

	// HTTP mux
	mux := http.NewServeMux()

	// Application routes
	mux.HandleFunc("/", handleRoot)
	mux.HandleFunc("/healthz", handleHealthz)
	mux.HandleFunc("/ready", handleReady)
	mux.HandleFunc("/version", handleVersion)

	// Application server (port 8080)
	appServer := &http.Server{
		Addr:         ":8080",
		Handler:      metricsMiddleware(mux),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Metrics server (port 9090) — separate to avoid mixing with app traffic
	metricsMux := http.NewServeMux()
	metricsMux.Handle("/metrics", promhttp.Handler())
	metricsServer := &http.Server{
		Addr:         ":9090",
		Handler:      metricsMux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
	}

	// Start servers
	go func() {
		slog.Info("Metrics server starting", "addr", ":9090")
		if err := metricsServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Metrics server failed", "error", err)
		}
	}()

	go func() {
		slog.Info("Application server starting", "addr", ":8080")
		// Mark as ready once server starts listening
		atomic.StoreInt32(&ready, 1)
		if err := appServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Application server failed", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for shutdown signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit

	slog.Info("Received shutdown signal", "signal", sig)

	// Mark as not ready immediately (fail readiness probe)
	atomic.StoreInt32(&ready, 0)

	// Give load balancer time to deregister
	slog.Info("Waiting for traffic drain", "duration", "5s")
	time.Sleep(5 * time.Second)

	// Graceful shutdown with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := appServer.Shutdown(ctx); err != nil {
		slog.Error("Application server forced shutdown", "error", err)
	}

	if err := metricsServer.Shutdown(ctx); err != nil {
		slog.Error("Metrics server forced shutdown", "error", err)
	}

	slog.Info("Servers stopped gracefully")
}

// handleRoot handles the main application endpoint
func handleRoot(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"message": "Hello from GitOps Platform!",
		"version": version,
	})
}

// handleHealthz handles liveness probe
func handleHealthz(w http.ResponseWriter, r *http.Request) {
	if atomic.LoadInt32(&healthy) == 1 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "OK"})
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "unhealthy"})
	}
}

// handleReady handles readiness probe
func handleReady(w http.ResponseWriter, r *http.Request) {
	if atomic.LoadInt32(&ready) == 1 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "not ready"})
	}
}

// handleVersion returns build information
func handleVersion(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"version":    version,
		"commit":     commit,
		"build_time": buildTime,
		"go_version": runtime.Version(),
	})
}
