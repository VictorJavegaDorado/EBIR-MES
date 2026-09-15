import { useEffect, useMemo, useRef, useState } from "react";
import {
  getLineAssignmentOptions,
  setLineAssignments,
  LineAssignmentApiError,
  type LineAssignmentOption,
} from "../api/lineAssignments";
import type { AuthorizedSupervisor } from "../../supervisor-access/api/authorizeSupervisorByRfid";

type Props = {
  supervisor: AuthorizedSupervisor;
  onSaved: () => void;
  onCancel: () => void;
};

export function LineAssignmentPicker({ supervisor, onSaved, onCancel }: Props) {
  const [options, setOptions] = useState<LineAssignmentOption[] | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [loadError, setLoadError] = useState("");
  const [saveError, setSaveError] = useState("");
  const [saving, setSaving] = useState(false);
  const initialized = useRef(false);

  useEffect(() => {
    const controller = new AbortController();
    getLineAssignmentOptions(controller.signal)
      .then((lines) => {
        setOptions(lines);
        if (!initialized.current) {
          initialized.current = true;
          setSelected(new Set(
            lines
              .filter((line) => line.supervisorNavEmployeeCode === supervisor.navEmployeeCode)
              .map((line) => line.lineId),
          ));
        }
      })
      .catch((caught) => {
        if (controller.signal.aborted) return;
        setLoadError(caught instanceof LineAssignmentApiError
          ? "No se pueden cargar las líneas disponibles."
          : "No se puede contactar con el panel de fabricación.");
      });
    return () => controller.abort();
  }, [supervisor.navEmployeeCode]);

  const groups = useMemo(() => {
    const byCenter = new Map<string, { workCenterName: string; lines: LineAssignmentOption[] }>();
    for (const line of options ?? []) {
      const group = byCenter.get(line.workCenterCode);
      if (group) group.lines.push(line);
      else byCenter.set(line.workCenterCode, { workCenterName: line.workCenterName, lines: [line] });
    }
    return Array.from(byCenter.entries());
  }, [options]);

  function toggle(line: LineAssignmentOption) {
    const lockedByOther = line.supervisorNavEmployeeCode !== null
      && line.supervisorNavEmployeeCode !== supervisor.navEmployeeCode;
    if (lockedByOther) return;
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(line.lineId)) next.delete(line.lineId);
      else next.add(line.lineId);
      return next;
    });
  }

  async function save() {
    setSaving(true);
    setSaveError("");
    try {
      await setLineAssignments(supervisor.employeeId, Array.from(selected));
      onSaved();
    } catch (caught) {
      if (caught instanceof LineAssignmentApiError && caught.code === "LINE_ASSIGNMENT_LOCKED") {
        setSaveError("Alguien más ha tomado una de esas líneas justo ahora. Revisa la selección.");
        const refreshed = await getLineAssignmentOptions().catch(() => null);
        if (refreshed) {
          setOptions(refreshed);
          setSelected((current) => new Set(
            Array.from(current).filter((lineId) => {
              const line = refreshed.find((item) => item.lineId === lineId);
              return !line || line.supervisorNavEmployeeCode === null
                || line.supervisorNavEmployeeCode === supervisor.navEmployeeCode;
            }),
          ));
        }
      } else if (caught instanceof LineAssignmentApiError && caught.code === "EMPLOYEE_NOT_ACTIVE_SUPERVISOR") {
        setSaveError("Tu tarjeta ya no corresponde a un jefe de línea vigente.");
      } else {
        setSaveError("No se ha podido guardar la selección. Prueba de nuevo.");
      }
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="dashboard-picker-page">
      <div className="dashboard-picker-card">
        <header className="dashboard-picker-head">
          <div className="dashboard-picker-avatar" aria-hidden="true">{initials(supervisor.fullName)}</div>
          <div>
            <strong>{supervisor.fullName}</strong>
            <span>jefe de línea · {supervisor.navEmployeeCode}</span>
          </div>
        </header>
        <p className="dashboard-picker-instructions">
          Elige las líneas que quieres ver en tu panel. Puedes cambiarlas cuando quieras
          volviendo a identificarte.
        </p>

        {loadError && <p className="dashboard-identify-error" role="alert">{loadError}</p>}
        {!loadError && !options && <p className="dashboard-picker-loading">Cargando líneas…</p>}

        {options && (
          <div className="dashboard-picker-groups">
            {groups.map(([workCenterCode, group]) => (
              <div className="dashboard-picker-group" key={workCenterCode}>
                <span className="dashboard-picker-group-label">
                  {workCenterCode} · {group.workCenterName}
                </span>
                <div className="dashboard-picker-lines">
                  {group.lines.map((line) => {
                    const lockedByOther = line.supervisorNavEmployeeCode !== null
                      && line.supervisorNavEmployeeCode !== supervisor.navEmployeeCode;
                    const checked = selected.has(line.lineId);
                    return (
                      <label
                        key={line.lineId}
                        className={`dashboard-picker-line${checked ? " checked" : ""}${lockedByOther ? " locked" : ""}`}
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          disabled={lockedByOther}
                          onChange={() => toggle(line)}
                        />
                        <span className="dashboard-picker-line-code">{line.lineCode}</span>
                        <span className="dashboard-picker-line-name">{line.lineName}</span>
                        {lockedByOther && (
                          <span className="dashboard-picker-lock-tag">
                            bloqueada · {line.supervisorName}
                          </span>
                        )}
                      </label>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        )}

        <p className="dashboard-picker-legend">
          🔒 Una línea bloqueada la lleva otro jefe. Se libera cuando él la desmarca desde su
          propio panel.
        </p>

        {saveError && <p className="dashboard-identify-error" role="alert">{saveError}</p>}

        <div className="dashboard-picker-footer">
          <span className="dashboard-picker-count">
            {selected.size} {selected.size === 1 ? "línea seleccionada" : "líneas seleccionadas"}
          </span>
          <div className="dashboard-picker-footer-actions">
            <button type="button" className="dashboard-identify-skip" onClick={onCancel} disabled={saving}>
              Cancelar
            </button>
            <button type="button" onClick={() => void save()} disabled={saving || !options}>
              {saving ? "Guardando…" : "Guardar y ver mi panel"}
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}

function initials(fullName: string) {
  return fullName.split(/\s+/).filter(Boolean).slice(0, 2)
    .map((part) => part[0]).join("").toLocaleUpperCase("es-ES");
}
