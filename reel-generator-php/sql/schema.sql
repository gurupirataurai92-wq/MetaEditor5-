-- Reel Generator — MySQL / MariaDB schema (XAMPP)
--
-- Import options:
--   * phpMyAdmin  → Import → choose this file
--   * CLI         → mysql -u root < sql/schema.sql
--   * Automatic   → the app self-installs + upgrades on first run (see includes/db.php)
--
-- Safe to run repeatedly: everything uses IF NOT EXISTS.

CREATE DATABASE IF NOT EXISTS `reel_generator`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE `reel_generator`;

CREATE TABLE IF NOT EXISTS `reels` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `topic`          VARCHAR(255)  NOT NULL,
  `script`         TEXT          NULL,
  `voice_id`       VARCHAR(64)   NOT NULL DEFAULT 'narrator-warm',
  `caption_style`  VARCHAR(64)   NOT NULL DEFAULT 'karaoke-bold-yellow',
  `music_track_id` VARCHAR(64)   NOT NULL DEFAULT 'lofi-01',
  `aspect`         VARCHAR(8)    NOT NULL DEFAULT '9:16',
  `fps`            SMALLINT UNSIGNED NOT NULL DEFAULT 30,
  `duration_sec`   DECIMAL(6,2)  NOT NULL DEFAULT 0,
  -- Look & length options
  `render_style`   ENUM('realistic','cartoon') NOT NULL DEFAULT 'cartoon',
  `length_mode`    ENUM('short','long')        NOT NULL DEFAULT 'short',
  `source`         ENUM('generated','uploaded') NOT NULL DEFAULT 'generated',
  -- Real video-provider linkage (filled when a provider renders an actual file)
  `provider`       VARCHAR(64)   NULL,
  `video_path`     VARCHAR(255)  NULL,
  `external_job_id` VARCHAR(191) NULL,
  `status`         ENUM('queued','scripting','voicing','sourcing_visuals','captioning','assembling','rendering','done','failed')
                                 NOT NULL DEFAULT 'queued',
  `progress`       DECIMAL(4,3)  NOT NULL DEFAULT 0,
  `output_url`     VARCHAR(255)  NULL,
  `error`          VARCHAR(255)  NULL,
  `created_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_reels_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `scenes` (
  `id`             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reel_id`        INT UNSIGNED NOT NULL,
  `scene_index`    SMALLINT UNSIGNED NOT NULL,
  `text`           TEXT          NOT NULL,
  `start_sec`      DECIMAL(6,2)  NOT NULL,
  `end_sec`        DECIMAL(6,2)  NOT NULL,
  `visual_type`    VARCHAR(16)   NOT NULL DEFAULT 'stock',
  `visual_query`   VARCHAR(191)  NOT NULL,
  `visual_asset_url` VARCHAR(255) NULL,
  `motion`         VARCHAR(16)   NOT NULL DEFAULT 'zoom-in',
  `caption_style`  VARCHAR(64)   NOT NULL DEFAULT 'karaoke-bold-yellow',
  `transition_out` VARCHAR(16)   NOT NULL DEFAULT 'fade',
  PRIMARY KEY (`id`),
  KEY `idx_scenes_reel` (`reel_id`, `scene_index`),
  CONSTRAINT `fk_scenes_reel` FOREIGN KEY (`reel_id`) REFERENCES `reels` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `caption_words` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `reel_id`    INT UNSIGNED NOT NULL,
  `scene_id`   INT UNSIGNED NOT NULL,
  `ordinal`    SMALLINT UNSIGNED NOT NULL,
  `word`       VARCHAR(64)  NOT NULL,
  `start_sec`  DECIMAL(6,3) NOT NULL,
  `end_sec`    DECIMAL(6,3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_words_reel` (`reel_id`, `ordinal`),
  CONSTRAINT `fk_words_reel`  FOREIGN KEY (`reel_id`)  REFERENCES `reels`  (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_words_scene` FOREIGN KEY (`scene_id`) REFERENCES `scenes` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User-uploaded videos (source clips or finished videos to host/play).
CREATE TABLE IF NOT EXISTS `uploads` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `original_name` VARCHAR(255) NOT NULL,
  `stored_path`   VARCHAR(255) NOT NULL,
  `mime`          VARCHAR(100) NOT NULL,
  `size_bytes`    BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_uploads_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
