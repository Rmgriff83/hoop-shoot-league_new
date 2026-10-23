-- 2026-10-23: the Vortex card became the Magnet (data/cards.json vortex6 → magnet6).
-- Every online copy renames; the ledger rows keep their history.
UPDATE online_cards SET card_id = 'magnet6' WHERE card_id = 'vortex6';
UPDATE online_ledger SET card_id = 'magnet6' WHERE card_id = 'vortex6';
