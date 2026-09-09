export type LabelControlPallet = {
  palletId: number;
  palletNumber: number;
  goodQuantity: number;
  isLast: boolean;
  closedAtUtc: string;
  navOperationId: number | null;
  navState: string | null;
  labelId: number | null;
  labelState: string | null;
  printJobId: number | null;
  printState: string | null;
  printAttempts: number;
  hasIncident: boolean;
  canReprint: boolean;
};

export type LabelControlOrder = {
  orderId: number;
  orderNumber: string;
  productNumber: string;
  productDescription: string;
  orderState: string;
  lineId: number;
  lineCode: string;
  lineName: string;
  lastPalletClosedAtUtc: string;
  pallets: LabelControlPallet[];
};

export type LabelControlSnapshot = {
  serverTimeUtc: string;
  orders: LabelControlOrder[];
};
