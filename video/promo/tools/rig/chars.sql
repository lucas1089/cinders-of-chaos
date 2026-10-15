-- TEST ONLY: the rig's account "trailer" (password "test", the stock SHA-1 form; the engine upgrades it at the first
-- login) and its four characters. Positions: the temple of town 1. rig.sh char gives gear (/testkit) and the level.
-- NEVER run on a real server. The deletes only touch account 420 when it is the rig's own 'trailer' account; if a
-- real account holds id 420 the INSERT below fails and nothing of it is removed.
DELETE FROM players WHERE account_id = 420 AND EXISTS (SELECT 1 FROM accounts WHERE id = 420 AND name = 'trailer');
DELETE FROM accounts WHERE id = 420 AND name = 'trailer';
INSERT INTO accounts (id, name, password, type, premium_ends_at) VALUES (420, 'trailer', 'a94a8fe5ccb19ba61c4c0873d391e987982fbbd3', 1, 1922949784);
INSERT INTO players (`name`, `account_id`, `vocation`, `level`, `experience`, `health`, `healthmax`, `mana`, `manamax`, `cap`, `group_id`, `posx`, `posy`, `posz`, `town_id`, `conditions`, `sex`, `soul`, `stamina`, `looktype`, `maglevel`, `skill_sword`, `skill_axe`, `skill_club`, `skill_shielding`) VALUES
('Ilsabet', 420, 5, 1000, 16566949800, 5145, 5145, 29850, 29850, 10390, 1, 32957, 32076, 7, 1, '', 0, 100, 2520, 2063, 140, 10, 10, 10, 30),
('Haldric', 420, 14, 1000, 16566949800, 15065, 15065, 5050, 5050, 25390, 1, 32957, 32076, 7, 1, '', 1, 100, 2520, 2075, 10, 130, 130, 130, 100),
('Sorenne', 420, 24, 1000, 16566949800, 10065, 10065, 15050, 15050, 15390, 1, 32957, 32076, 7, 1, '', 0, 100, 2520, 2182, 90, 120, 120, 120, 100),
('Ysolde', 420, 22, 1000, 16566949800, 5145, 5145, 29850, 29850, 10390, 1, 32957, 32076, 7, 1, '', 0, 100, 2520, 2168, 130, 10, 10, 10, 30);
