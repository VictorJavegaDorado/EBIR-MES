import { useEffect, useState, type ReactNode } from "react";

type AppShellProps = {
  children: ReactNode;
};

const timeFormatter = new Intl.DateTimeFormat("es-ES", {
  hour: "2-digit",
  minute: "2-digit",
});

const dateFormatter = new Intl.DateTimeFormat("es-ES", {
  weekday: "long",
  day: "2-digit",
  month: "long",
});

export function AppShell({ children }: AppShellProps) {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <div className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="EBIR MES, inicio">
          <span className="brand-mark" aria-hidden="true">E</span>
          <span>
            <strong>EBIR</strong>
            <small>Manufacturing Execution</small>
          </span>
        </a>

        <div className="environment-pill">
          <span className="environment-dot" />
          Piloto TEST
        </div>

        <div className="clock" aria-label="Fecha y hora actuales">
          <strong>{timeFormatter.format(now)}</strong>
          <span>{dateFormatter.format(now)}</span>
        </div>
      </header>

      <main>{children}</main>

      <footer className="app-footer">
        <span>EBIR MES</span>
        <span className="footer-separator" />
        <span>Terminal de producción</span>
        <span className="footer-status">
          <span className="environment-dot" />
          Flujo operativo guiado
        </span>
      </footer>
    </div>
  );
}
