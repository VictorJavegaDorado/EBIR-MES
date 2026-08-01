export type ProductionOrder = {
  productionOrderId: number;
  orderNumber: string;
  productNumber: string;
  productDescription: string;
  lotNumber: string;
  targetQuantity: number;
  goodQuantity: number;
  reservedQuantity: number;
  scrapQuantity: number;
  runTimeMinutes: number;
  state: string;
  importedAtUtc: string;
};
