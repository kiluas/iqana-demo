// apps/web/src/main.tsx
import React from "react";
import ReactDOM from "react-dom/client";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  useNavigate,
} from "react-router-dom";
import "./index.css";
import { App } from "./App";
import { login, handleCallback, logout, isAuthed } from "./auth/auth";

function Protected({ children }: { children: React.ReactNode }) {
  return isAuthed() ? <>{children}</> : <Navigate to="/login" replace />;
}

function LoginPage() {
  // auto-redirect to Cognito Hosted UI; if you prefer a button, comment this out and render one.
  React.useEffect(() => {
    login();
  }, []);
  return (
    <div style={{ padding: 24 }}>
      <p>Redirecting to sign in / sign up…</p>
      <button onClick={() => login()}>Open login</button>
    </div>
  );
}

function CallbackPage() {
  const navigate = useNavigate();
  React.useEffect(() => {
    (async () => {
      try {
        const ok = await handleCallback();
        if (ok) navigate("/", { replace: true });
      } catch (e) {
        console.error(e);
        navigate("/login", { replace: true });
      }
    })();
  }, [navigate]);
  return <p style={{ padding: 24 }}>Finalizing login…</p>;
}

function LogoutPage() {
  React.useEffect(() => {
    logout();
  }, []);
  return <p style={{ padding: 24 }}>Signing out…</p>;
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route path="/auth/callback" element={<CallbackPage />} />
        <Route path="/logout" element={<LogoutPage />} />
        {/* Everything else requires auth */}
        <Route
          path="/*"
          element={
            <Protected>
              <App />
            </Protected>
          }
        />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
