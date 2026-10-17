CREATE TRIGGER trg_driver_offer_deadline BEFORE INSERT OR UPDATE OF created_at, expires_at, status ON public.driver_offers FOR EACH ROW EXECUTE FUNCTION enforce_driver_offer_deadline();
CREATE TRIGGER trg_enforce_driver_offer_minimum_lifetime BEFORE INSERT OR UPDATE OF expires_at, status ON public.driver_offers FOR EACH ROW EXECUTE FUNCTION enforce_driver_offer_minimum_lifetime();
