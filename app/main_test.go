package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealthz(t *testing.T) {
	s := newServer("hi", "")
	rec := httptest.NewRecorder()
	s.routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("got %d, want 200", rec.Code)
	}
}

func TestReadyzReflectsState(t *testing.T) {
	s := newServer("hi", "")
	h := s.routes()

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("before ready: got %d, want 503", rec.Code)
	}

	s.ready.Store(true)
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("after ready: got %d, want 200", rec.Code)
	}
}

func TestHelloUsesConfiguredGreeting(t *testing.T) {
	s := newServer("bonjour", "")
	rec := httptest.NewRecorder()
	s.routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/hello", nil))
	if !strings.Contains(rec.Body.String(), "bonjour") {
		t.Fatalf("body %q missing greeting", rec.Body.String())
	}
}

func TestCreateItem(t *testing.T) {
	tests := []struct {
		name   string
		token  string
		header string
		body   string
		want   int
	}{
		{"no token configured", "", "Bearer x", `{"name":"a"}`, http.StatusUnauthorized},
		{"wrong token", "secret", "Bearer nope", `{"name":"a"}`, http.StatusUnauthorized},
		{"bad body", "secret", "Bearer secret", `{}`, http.StatusBadRequest},
		{"ok", "secret", "Bearer secret", `{"name":"a"}`, http.StatusCreated},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := newServer("hi", tc.token)
			req := httptest.NewRequest(http.MethodPost, "/api/v1/items", strings.NewReader(tc.body))
			req.Header.Set("Authorization", tc.header)
			rec := httptest.NewRecorder()
			s.routes().ServeHTTP(rec, req)
			if rec.Code != tc.want {
				t.Fatalf("got %d, want %d (body %q)", rec.Code, tc.want, rec.Body.String())
			}
		})
	}
}

func TestListItems(t *testing.T) {
	s := newServer("hi", "")
	s.store.add("widget")
	rec := httptest.NewRecorder()
	s.routes().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/items", nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "widget") {
		t.Fatalf("got %d %q", rec.Code, rec.Body.String())
	}
}
