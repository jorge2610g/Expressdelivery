-- La liquidación manual de una deuda de ajuste fallaba siempre con
-- «duplicate key … admin_financial_operations_adjustment_debt_id_uq»: el registro de creación del
-- ajuste (wallet_adjustment) y el de liquidación (debt_settlement) llevan el mismo
-- admin_adjustment_debt_id y la restricción permitía solo uno por deuda.
-- Se separa en dos garantías: una creación y una liquidación por deuda.
alter table public.admin_financial_operations
  drop constraint admin_financial_operations_adjustment_debt_id_uq;
create unique index admin_financial_operations_adjustment_debt_creation_uq
  on public.admin_financial_operations (admin_adjustment_debt_id)
  where operation_type = 'wallet_adjustment' and admin_adjustment_debt_id is not null;
create unique index admin_financial_operations_adjustment_debt_settlement_uq
  on public.admin_financial_operations (admin_adjustment_debt_id)
  where operation_type = 'debt_settlement' and admin_adjustment_debt_id is not null;
