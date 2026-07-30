export type IdentifiedLine = {
  id: number;
  code: string;
  name: string;
  workCenterCode: string;
  workCenterName: string;
  operationalStatus: string;
};

export type IdentificationViewState =
  | { status: "idle" }
  | { status: "loading"; code: string }
  | { status: "found"; line: IdentifiedLine }
  | { status: "error"; code: string; message: string };
