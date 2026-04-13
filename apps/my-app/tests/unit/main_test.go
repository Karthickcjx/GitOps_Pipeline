package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func TestHandleRoot(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	handleRoot(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rec.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if body["message"] != "Hello from GitOps Platform!" {
		t.Errorf("unexpected message: %s", body["message"])
	}
}

func TestHandleHealthz(t *testing.T) {
	tests := []struct {
		name       string
		healthy    int32
		wantStatus int
		wantBody   string
	}{
		{"healthy", 1, http.StatusOK, "OK"},
		{"unhealthy", 0, http.StatusServiceUnavailable, "unhealthy"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			atomic.StoreInt32(&healthy, tt.healthy)

			req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
			rec := httptest.NewRecorder()

			handleHealthz(rec, req)

			if rec.Code != tt.wantStatus {
				t.Errorf("expected status %d, got %d", tt.wantStatus, rec.Code)
			}

			var body map[string]string
			json.NewDecoder(rec.Body).Decode(&body)
			if body["status"] != tt.wantBody {
				t.Errorf("expected status %q, got %q", tt.wantBody, body["status"])
			}
		})
	}

	// Reset
	atomic.StoreInt32(&healthy, 1)
}

func TestHandleReady(t *testing.T) {
	tests := []struct {
		name       string
		ready      int32
		wantStatus int
		wantBody   string
	}{
		{"ready", 1, http.StatusOK, "ready"},
		{"not ready", 0, http.StatusServiceUnavailable, "not ready"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			atomic.StoreInt32(&ready, tt.ready)

			req := httptest.NewRequest(http.MethodGet, "/ready", nil)
			rec := httptest.NewRecorder()

			handleReady(rec, req)

			if rec.Code != tt.wantStatus {
				t.Errorf("expected status %d, got %d", tt.wantStatus, rec.Code)
			}

			var body map[string]string
			json.NewDecoder(rec.Body).Decode(&body)
			if body["status"] != tt.wantBody {
				t.Errorf("expected status %q, got %q", tt.wantBody, body["status"])
			}
		})
	}
}

func TestHandleVersion(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	rec := httptest.NewRecorder()

	handleVersion(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", rec.Code)
	}

	var body map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	requiredFields := []string{"version", "commit", "build_time", "go_version"}
	for _, field := range requiredFields {
		if _, ok := body[field]; !ok {
			t.Errorf("missing field in version response: %s", field)
		}
	}
}

func TestHandleRoot_NotFound(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/nonexistent", nil)
	rec := httptest.NewRecorder()

	handleRoot(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Errorf("expected status 404, got %d", rec.Code)
	}
}
