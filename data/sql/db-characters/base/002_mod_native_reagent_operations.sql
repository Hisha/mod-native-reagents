-- Additive safety journal. The two mod-bank-reagents compatibility tables are unchanged.
CREATE TABLE IF NOT EXISTS `character_native_reagent_operations` (
  `guid` INT UNSIGNED NOT NULL,
  `operation_id` BIGINT UNSIGNED NOT NULL,
  `kind` VARCHAR(16) NOT NULL,
  `state` VARCHAR(16) NOT NULL,
  `item_entry` INT UNSIGNED NOT NULL DEFAULT 0,
  `amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `result_amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`guid`, `operation_id`),
  KEY `idx_native_reagent_operation_state` (`guid`, `state`),
  KEY `idx_native_reagent_operation_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_native_reagent_operation_items` (
  `guid` INT UNSIGNED NOT NULL,
  `operation_id` BIGINT UNSIGNED NOT NULL,
  `item_entry` INT UNSIGNED NOT NULL,
  `amount` BIGINT UNSIGNED NOT NULL,
  `baseline` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `operation_id`, `item_entry`),
  CONSTRAINT `fk_native_reagent_operation_items`
    FOREIGN KEY (`guid`, `operation_id`)
    REFERENCES `character_native_reagent_operations` (`guid`, `operation_id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
