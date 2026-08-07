-- =============================================================================
--  Lymond Services — database schema and starter data
--  MySQL / MariaDB (the version bundled with XAMPP is fine)
--
--  HOW TO LOAD THIS
--    1. Start Apache and MySQL in the XAMPP control panel.
--    2. Open http://localhost/phpmyadmin
--    3. Click the "Import" tab, choose this file, then press "Go".
--
--  It creates the database, so you do not need to make one first.
--  Running it a second time WIPES the tables and puts the starter data back.
-- =============================================================================

CREATE DATABASE IF NOT EXISTS `lymond_services`
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `lymond_services`;

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS `activity_log`, `login_attempts`, `enquiries`, `photos`,
                     `parts`, `part_categories`, `vehicles`, `settings`, `operators`;
SET FOREIGN_KEY_CHECKS = 1;

-- -----------------------------------------------------------------------------
--  Operators — the staff who manage the catalogue
--  role 'admin'    : everything, including adding and removing operators
--  role 'operator' : stock, photos and enquiries
-- -----------------------------------------------------------------------------
CREATE TABLE `operators` (
  `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `username`      VARCHAR(60)  NOT NULL,
  `name`          VARCHAR(120) NOT NULL,
  `email`         VARCHAR(190) DEFAULT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `role`          ENUM('admin','operator') NOT NULL DEFAULT 'operator',
  `is_active`     TINYINT(1)   NOT NULL DEFAULT 1,
  `last_login_at` DATETIME     DEFAULT NULL,
  `created_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_operators_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Site settings — company details shown across the website
-- -----------------------------------------------------------------------------
CREATE TABLE `settings` (
  `name`  VARCHAR(60) NOT NULL,
  `value` TEXT        NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Vehicles
-- -----------------------------------------------------------------------------
CREATE TABLE `vehicles` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ref`          VARCHAR(20)  NOT NULL,
  `make`         VARCHAR(60)  NOT NULL,
  `model`        VARCHAR(120) NOT NULL,
  `year`         SMALLINT UNSIGNED NOT NULL,
  `body`         ENUM('sedan','hatchback','suv','van','pickup','truck') NOT NULL DEFAULT 'sedan',
  `fuel`         ENUM('Petrol','Diesel','Hybrid','Electric') NOT NULL DEFAULT 'Petrol',
  `transmission` ENUM('Automatic','Manual') NOT NULL DEFAULT 'Automatic',
  `engine`       VARCHAR(40)  DEFAULT NULL,
  `mileage`      INT UNSIGNED NOT NULL DEFAULT 0,
  `drive`        ENUM('2WD','4WD','AWD') NOT NULL DEFAULT '2WD',
  `colour`       VARCHAR(60)  DEFAULT NULL,
  `price`        DECIMAL(10,2) NOT NULL DEFAULT 0,
  `status`       ENUM('in-stock','in-transit','to-order') NOT NULL DEFAULT 'in-stock',
  `grade`        VARCHAR(6)   DEFAULT NULL,
  `steering`     ENUM('RHD','LHD') NOT NULL DEFAULT 'RHD',
  `note`         VARCHAR(255) DEFAULT NULL,
  `is_published` TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by`   INT UNSIGNED DEFAULT NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_vehicles_ref` (`ref`),
  KEY `ix_vehicles_browse` (`is_published`,`status`,`price`),
  KEY `ix_vehicles_body` (`body`),
  KEY `ix_vehicles_make` (`make`),
  CONSTRAINT `fk_vehicles_operator` FOREIGN KEY (`created_by`)
    REFERENCES `operators` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Spare parts
-- -----------------------------------------------------------------------------
CREATE TABLE `part_categories` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `slug`       VARCHAR(40)  NOT NULL,
  `name`       VARCHAR(80)  NOT NULL,
  `blurb`      VARCHAR(255) DEFAULT NULL,
  `sort_order` SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_part_categories_slug` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `parts` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `ref`          VARCHAR(20)  NOT NULL,
  `name`         VARCHAR(160) NOT NULL,
  `category_id`  INT UNSIGNED NOT NULL,
  `sku`          VARCHAR(60)  NOT NULL,
  `brand`        VARCHAR(80)  DEFAULT NULL,
  `type`         ENUM('genuine','oem','aftermarket','used') NOT NULL DEFAULT 'oem',
  `size`         ENUM('small','medium','large') NOT NULL DEFAULT 'small',
  `price`        DECIMAL(10,2) NOT NULL DEFAULT 0,
  `stock`        ENUM('in-stock','order') NOT NULL DEFAULT 'in-stock',
  `fits`         VARCHAR(400) DEFAULT NULL,
  `note`         VARCHAR(255) DEFAULT NULL,
  `is_published` TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by`   INT UNSIGNED DEFAULT NULL,
  `created_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_parts_ref` (`ref`),
  KEY `ix_parts_browse` (`is_published`,`category_id`,`size`),
  KEY `ix_parts_sku` (`sku`),
  CONSTRAINT `fk_parts_category` FOREIGN KEY (`category_id`)
    REFERENCES `part_categories` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_parts_operator` FOREIGN KEY (`created_by`)
    REFERENCES `operators` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Photos — one row per uploaded picture, for a vehicle or a part.
--  The lowest sort_order is the cover shown on the card.
-- -----------------------------------------------------------------------------
CREATE TABLE `photos` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `item_type`  ENUM('vehicle','part') NOT NULL,
  `item_id`    INT UNSIGNED NOT NULL,
  `filename`   VARCHAR(160) NOT NULL,
  `sort_order` INT          NOT NULL DEFAULT 0,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_photos_item` (`item_type`,`item_id`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Enquiries from the contact form
-- -----------------------------------------------------------------------------
CREATE TABLE `enquiries` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name`       VARCHAR(120) NOT NULL,
  `email`      VARCHAR(190) NOT NULL,
  `phone`      VARCHAR(40)  DEFAULT NULL,
  `topic`      VARCHAR(60)  NOT NULL,
  `message`    TEXT         NOT NULL,
  `ref`        VARCHAR(40)  DEFAULT NULL,
  `status`     ENUM('new','in-progress','closed') NOT NULL DEFAULT 'new',
  `handled_by` INT UNSIGNED DEFAULT NULL,
  `ip`         VARCHAR(45)  DEFAULT NULL,
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_enquiries_status` (`status`,`created_at`),
  CONSTRAINT `fk_enquiries_operator` FOREIGN KEY (`handled_by`)
    REFERENCES `operators` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
--  Sign-in attempts (used to slow down guessing) and the activity log
-- -----------------------------------------------------------------------------
CREATE TABLE `login_attempts` (
  `id`           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `username`     VARCHAR(60) NOT NULL,
  `ip`           VARCHAR(45) NOT NULL,
  `ok`           TINYINT(1)  NOT NULL DEFAULT 0,
  `attempted_at` DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_attempts` (`username`,`ip`,`attempted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `activity_log` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `operator_id` INT UNSIGNED DEFAULT NULL,
  `action`      VARCHAR(80)  NOT NULL,
  `detail`      VARCHAR(255) DEFAULT NULL,
  `ip`          VARCHAR(45)  DEFAULT NULL,
  `happened_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `ix_activity_time` (`happened_at`),
  CONSTRAINT `fk_activity_operator` FOREIGN KEY (`operator_id`)
    REFERENCES `operators` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
--  STARTER DATA
-- =============================================================================

-- Two accounts to begin with. CHANGE BOTH PASSWORDS after your first sign-in:
--   admin    / Lymond#2026     (administrator — can also manage operators)
--   operator / Operator#2026   (day-to-day stock and enquiries)

INSERT INTO `operators` (`username`,`name`,`email`,`password_hash`,`role`) VALUES
  ('admin','Site Administrator','admin@lymondservices.example','$2y$12$.BbW6xGuiwLz54WxiH2qo.HSg34NDdvVa02/IPQQ/8SRJu8QA0.uK','admin'),
  ('operator','Counter Operator','parts@lymondservices.example','$2y$12$YTzlxHbCCY8R5UPtiWz3JufSoLvaOHw7iMjQUHVTMZQMIE4quQcpO','operator');

INSERT INTO `settings` (`name`,`value`) VALUES
  ('company_name','Lymond Services'),
  ('tagline','Japanese imports & spare parts'),
  ('phone','+255 754 000 111'),
  ('whatsapp','+255 754 000 111'),
  ('email','sales@lymondservices.example'),
  ('parts_email','parts@lymondservices.example'),
  ('address','Plot 44, Nyerere Road, Dar es Salaam, Tanzania'),
  ('hours','Mon–Fri 08:00–18:00 · Sat 09:00–15:00'),
  ('stat_vehicles','2,400+'),
  ('stat_parts','18,000'),
  ('stat_sailing','21 days'),
  ('stat_years','12 years');

INSERT INTO `part_categories` (`id`,`slug`,`name`,`blurb`,`sort_order`) VALUES
  (1,'engine','Engine & Cooling','Complete engines, half-cuts, gaskets, pumps, radiators and belts.',10),
  (2,'brakes','Brakes & Clutch','Pads, discs, callipers, master cylinders, clutch kits and hoses.',20),
  (3,'suspension','Suspension & Steering','Shocks, springs, bushes, ball joints, racks and tie rods.',30),
  (4,'electrical','Electrical & Sensors','Batteries, alternators, starters, ECUs, sensors and lamps.',40),
  (5,'filters','Filters & Service Kits','Oil, air, fuel and cabin filters plus full service bundles.',50),
  (6,'body','Body & Interior','Bumpers, mirrors, doors, lights, grilles and trim panels.',60),
  (7,'tyres','Tyres & Rims','New and used tyres, alloy and steel rims, valves and nuts.',70),
  (8,'transmission','Transmission & Drive','Gearboxes, diffs, CV joints, drive shafts and mounts.',80);

INSERT INTO `vehicles` (`ref`,`make`,`model`,`year`,`body`,`fuel`,`transmission`,`engine`,`mileage`,`drive`,`colour`,`price`,`status`,`grade`,`steering`,`note`,`created_by`) VALUES
  ('V-001','Toyota','Land Cruiser Prado TX',2018,'suv','Diesel','Automatic','2755 cc',68000,'4WD','Pearl White',32500,'in-stock','4.5','RHD','Sunroof, leather trim, reverse camera. Cleared and registered.',1),
  ('V-002','Toyota','Hilux Double Cab',2019,'pickup','Diesel','Manual','2393 cc',54000,'4WD','Silver',26900,'in-stock','4.5','RHD','Fitted with bed liner and roll bar. Ideal for site work.',1),
  ('V-003','Toyota','Vitz F',2017,'hatchback','Petrol','Automatic','996 cc',72000,'2WD','Red',6450,'in-stock','4','RHD','Low running cost city car, fresh import, service book present.',1),
  ('V-004','Nissan','X-Trail 20X',2018,'suv','Petrol','Automatic','1997 cc',61000,'4WD','Gunmetal',15800,'in-stock','4.5','RHD','Hydraulic suspension, roof rails, half-leather seats.',1),
  ('V-005','Toyota','Noah Si',2016,'van','Petrol','Automatic','1986 cc',88000,'2WD','White',11200,'in-transit','4','RHD','8-seater family van, power sliding doors. ETA 3 weeks.',1),
  ('V-006','Mitsubishi','Canter Freezer Truck',2015,'truck','Diesel','Manual','2998 cc',145000,'2WD','White',21400,'in-transit','3.5','RHD','3-ton refrigerated body, unit tested and working. ETA 4 weeks.',1),
  ('V-007','Honda','Fit Hybrid',2019,'hatchback','Hybrid','Automatic','1496 cc',45000,'2WD','Blue',8900,'in-stock','4.5','RHD','Excellent fuel economy, push start, alloy wheels.',1),
  ('V-008','Toyota','Corolla Axio',2018,'sedan','Petrol','Automatic','1496 cc',59000,'2WD','Black',9750,'in-stock','4.5','RHD','Popular taxi and family sedan, cheap to run and service.',1),
  ('V-009','Subaru','Forester X-Break',2017,'suv','Petrol','Automatic','1995 cc',74000,'AWD','Orange',14300,'in-stock','4','RHD','Symmetrical AWD, X-Mode, water-repellent seats.',1),
  ('V-010','Toyota','Hiace Van GL',2016,'van','Diesel','Manual','2982 cc',132000,'2WD','White',18600,'in-stock','4','RHD','Long body, 14-seat conversion available on request.',1),
  ('V-011','Mazda','CX-5 XD',2018,'suv','Diesel','Automatic','2188 cc',63000,'AWD','Soul Red',17400,'to-order','4.5','RHD','Sourced to order from Japanese auctions — 4 to 6 weeks.',1),
  ('V-012','Nissan','Note e-Power',2019,'hatchback','Hybrid','Automatic','1198 cc',38000,'2WD','White Pearl',9200,'in-stock','5','RHD',NULL,1),
  ('V-013','Toyota','Premio F',2017,'sedan','Petrol','Automatic','1797 cc',66000,'2WD','Beige',11800,'in-stock','4.5','RHD',NULL,1),
  ('V-014','Isuzu','Elf Tipper',2014,'truck','Diesel','Manual','4570 cc',168000,'2WD','Blue',23800,'to-order','3.5','RHD','4-ton hydraulic tipper. Auction sourcing on request.',1),
  ('V-015','Suzuki','Every Wagon',2018,'van','Petrol','Automatic','658 cc',52000,'2WD','Silver',6800,'in-transit','4','RHD',NULL,1),
  ('V-016','Toyota','Harrier Premium',2019,'suv','Petrol','Automatic','1998 cc',41000,'2WD','Precious Black',27600,'in-stock','5','RHD','Top-grade unit, panoramic roof, JBL sound, 360° camera.',1),
  ('V-017','Nissan','Navara NP300',2018,'pickup','Diesel','Automatic','2298 cc',79000,'4WD','Grey',22400,'in-stock','4','RHD',NULL,1),
  ('V-018','Honda','Vezel Hybrid Z',2018,'suv','Hybrid','Automatic','1496 cc',49000,'2WD','White',13900,'in-stock','4.5','RHD',NULL,1);

INSERT INTO `parts` (`ref`,`name`,`category_id`,`sku`,`brand`,`type`,`size`,`price`,`stock`,`fits`,`note`,`created_by`) VALUES
  ('P-001','Complete Engine Assembly 1NZ-FE',1,'ENG-1NZ-FE','Toyota Genuine','used','large',890,'in-stock','Toyota Vitz, Toyota Corolla Axio, Toyota Probox','Japan-removed half-cut engine, compression tested, 3-month warranty.',1),
  ('P-002','Radiator Assembly with Fan Shroud',1,'RAD-XT-2018','Koyorad','aftermarket','medium',165,'in-stock','Nissan X-Trail T32, Nissan Qashqai',NULL,1),
  ('P-003','Timing Chain Kit',1,'TCK-2AZ','Aisin','oem','small',210,'in-stock','Toyota 2AZ-FE engines',NULL,1),
  ('P-004','Water Pump',1,'WP-1KD','Aisin','oem','small',96,'in-stock','Toyota Hilux 1KD-FTV, Toyota Prado 1KD-FTV',NULL,1),
  ('P-005','Turbocharger (Reconditioned)',1,'TRB-1KD-RC','Toyota Genuine','used','medium',640,'order','Toyota Hilux, Toyota Prado','Bench tested, balanced core.',1),
  ('P-006','Front Brake Pad Set (Ceramic)',2,'BRK-PAD-LC','Advics','oem','small',68,'in-stock','Toyota Land Cruiser Prado 150, Toyota Hilux',NULL,1),
  ('P-007','Brake Disc Rotor (Pair)',2,'BRK-DSC-AXIO','Nisshinbo','aftermarket','medium',92,'in-stock','Toyota Corolla Axio, Toyota Premio',NULL,1),
  ('P-008','Clutch Kit (Cover, Plate, Bearing)',2,'CLT-KIT-HLX','Exedy','oem','medium',245,'in-stock','Toyota Hilux 2KD, Toyota Hiace',NULL,1),
  ('P-009','Brake Master Cylinder',2,'BRK-MC-NOAH','Toyota Genuine','oem','small',138,'order','Toyota Noah, Toyota Voxy',NULL,1),
  ('P-010','Front Shock Absorber (Each)',3,'SUS-SHK-XT','KYB','oem','medium',84,'in-stock','Nissan X-Trail, Nissan Serena',NULL,1),
  ('P-011','Lower Control Arm with Ball Joint',3,'SUS-LCA-FIT','CTR','aftermarket','medium',74,'in-stock','Honda Fit GK, Honda Vezel',NULL,1),
  ('P-012','Steering Rack (Reconditioned)',3,'STR-RCK-PRD','Toyota Genuine','used','large',410,'order','Toyota Prado 120, Toyota Hilux Vigo',NULL,1),
  ('P-013','Stabiliser Link Set',3,'SUS-SLK-PRM','555','oem','small',38,'in-stock','Toyota Premio, Toyota Allion, Toyota Corolla',NULL,1),
  ('P-014','Alternator 12V 100A',4,'ELE-ALT-2AZ','Denso','oem','medium',230,'in-stock','Toyota Noah, Toyota Ipsum, Toyota RAV4',NULL,1),
  ('P-015','Starter Motor',4,'ELE-STR-1KD','Denso','oem','medium',265,'in-stock','Toyota Hilux, Toyota Prado',NULL,1),
  ('P-016','Maintenance-Free Battery 70Ah',4,'ELE-BAT-70','Panasonic','aftermarket','medium',118,'in-stock','Most petrol saloons and SUVs',NULL,1),
  ('P-017','Oxygen (Lambda) Sensor',4,'ELE-O2-UNI','Denso','oem','small',79,'in-stock','Toyota, Nissan, Honda petrol engines',NULL,1),
  ('P-018','LED Headlamp Unit (Right)',4,'ELE-HDL-HRR','Koito','genuine','medium',385,'order','Toyota Harrier 2018+',NULL,1),
  ('P-019','Oil Filter',5,'FLT-OIL-90915','Toyota Genuine','genuine','small',9,'in-stock','Most Toyota petrol engines',NULL,1),
  ('P-020','Air Filter Element',5,'FLT-AIR-17801','Toyota Genuine','genuine','small',16,'in-stock','Toyota Vitz, Toyota Axio, Toyota Probox',NULL,1),
  ('P-021','Fuel Filter (Diesel, with Water Trap)',5,'FLT-FUL-DSL','Denso','oem','small',34,'in-stock','Toyota Hilux, Isuzu Elf, Mitsubishi Canter',NULL,1),
  ('P-022','Full Service Kit (Oil, Air, Cabin, Plugs)',5,'FLT-KIT-SRV','Mixed OEM','oem','small',78,'in-stock','Toyota Corolla Axio, Toyota Premio, Toyota Fielder','Everything needed for a 10,000 km service in one box.',1),
  ('P-023','Front Bumper (Unpainted)',6,'BDY-BMP-VTZ','Aftermarket','aftermarket','large',145,'in-stock','Toyota Vitz 2015-2019',NULL,1),
  ('P-024','Side Mirror Assembly (Power, Left)',6,'BDY-MIR-XT-L','Nissan Genuine','genuine','medium',168,'in-stock','Nissan X-Trail T32',NULL,1),
  ('P-025','Tail Lamp Assembly (Right)',6,'BDY-TL-HLX-R','Depo','aftermarket','medium',88,'in-stock','Toyota Hilux Revo',NULL,1),
  ('P-026','Bonnet / Hood Panel',6,'BDY-BNT-AXIO','Aftermarket','aftermarket','large',210,'order','Toyota Corolla Axio 2013-2018',NULL,1),
  ('P-027','Wiper Blade Pair',6,'BDY-WPR-UNI','NWB','oem','small',22,'in-stock','Universal fitment 14"–26"',NULL,1),
  ('P-028','Tyre 265/65 R17 All-Terrain',7,'TYR-265-65-17','Dunlop','aftermarket','large',195,'in-stock','Toyota Prado, Toyota Hilux, Ford Ranger',NULL,1),
  ('P-029','Tyre 185/65 R15',7,'TYR-185-65-15','Yokohama','aftermarket','medium',78,'in-stock','Toyota Axio, Honda Fit, Nissan Note',NULL,1),
  ('P-030','Alloy Rim 17" (Each)',7,'RIM-ALY-17','Japan Used','used','large',130,'in-stock','5x114.3 PCD vehicles',NULL,1),
  ('P-031','Wheel Nut Set (20 pcs)',7,'RIM-NUT-20','Aftermarket','aftermarket','small',24,'in-stock','M12 x 1.5 studs',NULL,1),
  ('P-032','Automatic Gearbox (Reconditioned)',8,'TRN-ATM-1NZ','Toyota Genuine','used','large',980,'order','Toyota Vitz, Toyota Axio, Toyota Sienta','Fluid flushed, road tested, 3-month exchange warranty.',1),
  ('P-033','CV Joint Kit (Outer)',8,'TRN-CVJ-FIT','GSP','aftermarket','small',62,'in-stock','Honda Fit, Honda Vezel, Honda Freed',NULL,1),
  ('P-034','Propeller Shaft Centre Bearing',8,'TRN-PSB-HLX','NTN','oem','small',55,'in-stock','Toyota Hilux, Toyota Hiace',NULL,1),
  ('P-035','Rear Differential Assembly',8,'TRN-DIF-PRD','Toyota Genuine','used','large',720,'order','Toyota Prado 120, Toyota Land Cruiser 100',NULL,1),
  ('P-036','Engine Mount Set',8,'TRN-MNT-NOAH','Tenneco','aftermarket','small',96,'in-stock','Toyota Noah, Toyota Voxy, Toyota Isis',NULL,1);

INSERT INTO `enquiries` (`name`,`email`,`phone`,`topic`,`message`,`ref`,`status`) VALUES
  ('Grace Mollel','grace@example.com','+255 754 111 222','Vehicle import',
   'Looking for a 2018 Toyota Hilux double cab, automatic, under 80,000 km. What can you land in Dar es Salaam for 27,000 USD?','V-002','new'),
  ('Kagera Motors','workshop@example.com','+255 767 900 100','Spare parts',
   'Need a front lower control arm for a Honda Fit GK, chassis GK3-1234567. Two pieces.','P-011','in-progress');

-- =============================================================================
--  Done. Open http://localhost/lymond/ for the site,
--  and http://localhost/lymond/admin/ to sign in as an operator.
-- =============================================================================
