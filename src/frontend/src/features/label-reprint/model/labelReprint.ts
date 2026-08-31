export type LabelReprintCommand = {
  requestedBySupervisorId: number;
  reason: string;
  correlationId: string;
};

export type QueuedLabelReprint = {
  id: number;
  palletId: number;
  correlationId: string;
};

export type LabelReprintSupervisor = {
  id: number;
  code: string;
  name: string;
};
