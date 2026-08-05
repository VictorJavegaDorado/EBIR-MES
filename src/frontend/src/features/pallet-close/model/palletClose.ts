export type PartialReason =
  | "FIN_TURNO"
  | "FALTA_MATERIAL"
  | "ULTIMO_PALET";

export type ClosePalletCommand = {
  goodQuantity: number;
  closedByEmployeeId: number;
  authorizingSupervisorId: number | null;
  isPartial: boolean;
  partialReason: PartialReason | null;
  correlationId: string;
};

export type ClosedPallet = {
  id: number;
  correlationId: string;
};

export type PalletReservationOption = {
  id: number;
  reservedQuantity: number;
  orderNumber: string;
  productNumber: string;
  productDescription: string;
  productPostingGroup: string;
  lineName: string;
};

export type PalletEmployeeOption = {
  id: number;
  code: string;
  name: string;
};

export type PalletCloseOptions = {
  reservations: PalletReservationOption[];
  employees: PalletEmployeeOption[];
  supervisors: PalletEmployeeOption[];
};

export type PalletCloseViewState =
  | { status: "idle" }
  | { status: "loading"; correlationId: string }
  | { status: "closed"; pallet: ClosedPallet }
  | {
      status: "error";
      code: string;
      message: string;
      retryable: boolean;
      correlationId?: string;
    };
