/* ==========================================================================
   Sakura Auto Imports — demo catalogue data
   --------------------------------------------------------------------------
   This is sample content for the front-end. Swap this file for a real API
   response (same field names) when the site is wired to a back office.
   Prices are indicative USD figures for demonstration only.
   ========================================================================== */

window.SITE = {
  company: {
    name: 'Sakura Auto Imports',
    tagline: 'Japanese imports & spare parts',
    phone: '+255 754 000 111',
    whatsapp: '+255 754 000 111',
    email: 'sales@sakura-autoimports.example',
    parts_email: 'parts@sakura-autoimports.example',
    address: 'Plot 44, Nyerere Road, Dar es Salaam, Tanzania',
    hours: 'Mon–Fri 08:00–18:00 · Sat 09:00–15:00',
    currency: 'USD'
  },

  /* ------------------------------------------------------------ vehicles -- */
  vehicles: [
    {
      id: 'v-001', make: 'Toyota', model: 'Land Cruiser Prado TX',
      year: 2018, body: 'suv', fuel: 'Diesel', transmission: 'Automatic',
      engine: '2755 cc', mileage: 68000, drive: '4WD', colour: 'Pearl White',
      price: 32500, status: 'in-stock', grade: '4.5', steering: 'RHD',
      note: 'Sunroof, leather trim, reverse camera. Cleared and registered.'
    },
    {
      id: 'v-002', make: 'Toyota', model: 'Hilux Double Cab',
      year: 2019, body: 'pickup', fuel: 'Diesel', transmission: 'Manual',
      engine: '2393 cc', mileage: 54000, drive: '4WD', colour: 'Silver',
      price: 26900, status: 'in-stock', grade: '4.5', steering: 'RHD',
      note: 'Fitted with bed liner and roll bar. Ideal for site work.'
    },
    {
      id: 'v-003', make: 'Toyota', model: 'Vitz F',
      year: 2017, body: 'hatchback', fuel: 'Petrol', transmission: 'Automatic',
      engine: '996 cc', mileage: 72000, drive: '2WD', colour: 'Red',
      price: 6450, status: 'in-stock', grade: '4', steering: 'RHD',
      note: 'Low running cost city car, fresh import, service book present.'
    },
    {
      id: 'v-004', make: 'Nissan', model: 'X-Trail 20X',
      year: 2018, body: 'suv', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1997 cc', mileage: 61000, drive: '4WD', colour: 'Gunmetal',
      price: 15800, status: 'in-stock', grade: '4.5', steering: 'RHD',
      note: 'Hydraulic suspension, roof rails, half-leather seats.'
    },
    {
      id: 'v-005', make: 'Toyota', model: 'Noah Si',
      year: 2016, body: 'van', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1986 cc', mileage: 88000, drive: '2WD', colour: 'White',
      price: 11200, status: 'in-transit', grade: '4', steering: 'RHD',
      note: '8-seater family van, power sliding doors. ETA 3 weeks.'
    },
    {
      id: 'v-006', make: 'Mitsubishi', model: 'Canter Freezer Truck',
      year: 2015, body: 'truck', fuel: 'Diesel', transmission: 'Manual',
      engine: '2998 cc', mileage: 145000, drive: '2WD', colour: 'White',
      price: 21400, status: 'in-transit', grade: '3.5', steering: 'RHD',
      note: '3-ton refrigerated body, unit tested and working. ETA 4 weeks.'
    },
    {
      id: 'v-007', make: 'Honda', model: 'Fit Hybrid',
      year: 2019, body: 'hatchback', fuel: 'Hybrid', transmission: 'Automatic',
      engine: '1496 cc', mileage: 45000, drive: '2WD', colour: 'Blue',
      price: 8900, status: 'in-stock', grade: '4.5', steering: 'RHD',
      note: 'Excellent fuel economy, push start, alloy wheels.'
    },
    {
      id: 'v-008', make: 'Toyota', model: 'Corolla Axio',
      year: 2018, body: 'sedan', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1496 cc', mileage: 59000, drive: '2WD', colour: 'Black',
      price: 9750, status: 'in-stock', grade: '4.5', steering: 'RHD',
      note: 'Popular taxi and family sedan, cheap to run and service.'
    },
    {
      id: 'v-009', make: 'Subaru', model: 'Forester X-Break',
      year: 2017, body: 'suv', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1995 cc', mileage: 74000, drive: 'AWD', colour: 'Orange',
      price: 14300, status: 'in-stock', grade: '4', steering: 'RHD',
      note: 'Symmetrical AWD, X-Mode, water-repellent seats.'
    },
    {
      id: 'v-010', make: 'Toyota', model: 'Hiace Van GL',
      year: 2016, body: 'van', fuel: 'Diesel', transmission: 'Manual',
      engine: '2982 cc', mileage: 132000, drive: '2WD', colour: 'White',
      price: 18600, status: 'in-stock', grade: '4', steering: 'RHD',
      note: 'Long body, 14-seat conversion available on request.'
    },
    {
      id: 'v-011', make: 'Mazda', model: 'CX-5 XD',
      year: 2018, body: 'suv', fuel: 'Diesel', transmission: 'Automatic',
      engine: '2188 cc', mileage: 63000, drive: 'AWD', colour: 'Soul Red',
      price: 17400, status: 'to-order', grade: '4.5', steering: 'RHD',
      note: 'Sourced to order from Japanese auctions — 4 to 6 weeks.'
    },
    {
      id: 'v-012', make: 'Nissan', model: 'Note e-Power',
      year: 2019, body: 'hatchback', fuel: 'Hybrid', transmission: 'Automatic',
      engine: '1198 cc', mileage: 38000, drive: '2WD', colour: 'White Pearl',
      price: 9200, status: 'in-stock', grade: '5', steering: 'RHD'
    },
    {
      id: 'v-013', make: 'Toyota', model: 'Premio F',
      year: 2017, body: 'sedan', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1797 cc', mileage: 66000, drive: '2WD', colour: 'Beige',
      price: 11800, status: 'in-stock', grade: '4.5', steering: 'RHD'
    },
    {
      id: 'v-014', make: 'Isuzu', model: 'Elf Tipper',
      year: 2014, body: 'truck', fuel: 'Diesel', transmission: 'Manual',
      engine: '4570 cc', mileage: 168000, drive: '2WD', colour: 'Blue',
      price: 23800, status: 'to-order', grade: '3.5', steering: 'RHD',
      note: '4-ton hydraulic tipper. Auction sourcing on request.'
    },
    {
      id: 'v-015', make: 'Suzuki', model: 'Every Wagon',
      year: 2018, body: 'van', fuel: 'Petrol', transmission: 'Automatic',
      engine: '658 cc', mileage: 52000, drive: '2WD', colour: 'Silver',
      price: 6800, status: 'in-transit', grade: '4', steering: 'RHD'
    },
    {
      id: 'v-016', make: 'Toyota', model: 'Harrier Premium',
      year: 2019, body: 'suv', fuel: 'Petrol', transmission: 'Automatic',
      engine: '1998 cc', mileage: 41000, drive: '2WD', colour: 'Precious Black',
      price: 27600, status: 'in-stock', grade: '5', steering: 'RHD',
      note: 'Top-grade unit, panoramic roof, JBL sound, 360° camera.'
    },
    {
      id: 'v-017', make: 'Nissan', model: 'Navara NP300',
      year: 2018, body: 'pickup', fuel: 'Diesel', transmission: 'Automatic',
      engine: '2298 cc', mileage: 79000, drive: '4WD', colour: 'Grey',
      price: 22400, status: 'in-stock', grade: '4', steering: 'RHD'
    },
    {
      id: 'v-018', make: 'Honda', model: 'Vezel Hybrid Z',
      year: 2018, body: 'suv', fuel: 'Hybrid', transmission: 'Automatic',
      engine: '1496 cc', mileage: 49000, drive: '2WD', colour: 'White',
      price: 13900, status: 'in-stock', grade: '4.5', steering: 'RHD'
    }
  ],

  /* ---------------------------------------------------------- categories -- */
  partCategories: [
    { id: 'engine',       name: 'Engine & Cooling',      blurb: 'Complete engines, half-cuts, gaskets, pumps, radiators and belts.' },
    { id: 'brakes',       name: 'Brakes & Clutch',        blurb: 'Pads, discs, callipers, master cylinders, clutch kits and hoses.' },
    { id: 'suspension',   name: 'Suspension & Steering',  blurb: 'Shocks, springs, bushes, ball joints, racks and tie rods.' },
    { id: 'electrical',   name: 'Electrical & Sensors',   blurb: 'Batteries, alternators, starters, ECUs, sensors and lamps.' },
    { id: 'filters',      name: 'Filters & Service Kits', blurb: 'Oil, air, fuel and cabin filters plus full service bundles.' },
    { id: 'body',         name: 'Body & Interior',        blurb: 'Bumpers, mirrors, doors, lights, grilles and trim panels.' },
    { id: 'tyres',        name: 'Tyres & Rims',           blurb: 'New and used tyres, alloy and steel rims, valves and nuts.' },
    { id: 'transmission', name: 'Transmission & Drive',   blurb: 'Gearboxes, diffs, CV joints, drive shafts and mounts.' }
  ],

  /* --------------------------------------------------------------- parts -- */
  parts: [
    { id: 'p-001', name: 'Complete Engine Assembly 1NZ-FE', category: 'engine', sku: 'ENG-1NZ-FE',
      brand: 'Toyota Genuine', type: 'used', price: 890, stock: 'in-stock', size: 'large',
      fits: ['Toyota Vitz', 'Toyota Corolla Axio', 'Toyota Probox'],
      note: 'Japan-removed half-cut engine, compression tested, 3-month warranty.' },
    { id: 'p-002', name: 'Radiator Assembly with Fan Shroud', category: 'engine', sku: 'RAD-XT-2018',
      brand: 'Koyorad', type: 'aftermarket', price: 165, stock: 'in-stock', size: 'medium',
      fits: ['Nissan X-Trail T32', 'Nissan Qashqai'] },
    { id: 'p-003', name: 'Timing Chain Kit', category: 'engine', sku: 'TCK-2AZ',
      brand: 'Aisin', type: 'oem', price: 210, stock: 'in-stock', size: 'small',
      fits: ['Toyota 2AZ-FE engines'] },
    { id: 'p-004', name: 'Water Pump', category: 'engine', sku: 'WP-1KD',
      brand: 'Aisin', type: 'oem', price: 96, stock: 'in-stock', size: 'small',
      fits: ['Toyota Hilux 1KD-FTV', 'Toyota Prado 1KD-FTV'] },
    { id: 'p-005', name: 'Turbocharger (Reconditioned)', category: 'engine', sku: 'TRB-1KD-RC',
      brand: 'Toyota Genuine', type: 'used', price: 640, stock: 'order', size: 'medium',
      fits: ['Toyota Hilux', 'Toyota Prado'], note: 'Bench tested, balanced core.' },

    { id: 'p-006', name: 'Front Brake Pad Set (Ceramic)', category: 'brakes', sku: 'BRK-PAD-LC',
      brand: 'Advics', type: 'oem', price: 68, stock: 'in-stock', size: 'small',
      fits: ['Toyota Land Cruiser Prado 150', 'Toyota Hilux'] },
    { id: 'p-007', name: 'Brake Disc Rotor (Pair)', category: 'brakes', sku: 'BRK-DSC-AXIO',
      brand: 'Nisshinbo', type: 'aftermarket', price: 92, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Corolla Axio', 'Toyota Premio'] },
    { id: 'p-008', name: 'Clutch Kit (Cover, Plate, Bearing)', category: 'brakes', sku: 'CLT-KIT-HLX',
      brand: 'Exedy', type: 'oem', price: 245, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Hilux 2KD', 'Toyota Hiace'] },
    { id: 'p-009', name: 'Brake Master Cylinder', category: 'brakes', sku: 'BRK-MC-NOAH',
      brand: 'Toyota Genuine', type: 'oem', price: 138, stock: 'order', size: 'small',
      fits: ['Toyota Noah', 'Toyota Voxy'] },

    { id: 'p-010', name: 'Front Shock Absorber (Each)', category: 'suspension', sku: 'SUS-SHK-XT',
      brand: 'KYB', type: 'oem', price: 84, stock: 'in-stock', size: 'medium',
      fits: ['Nissan X-Trail', 'Nissan Serena'] },
    { id: 'p-011', name: 'Lower Control Arm with Ball Joint', category: 'suspension', sku: 'SUS-LCA-FIT',
      brand: 'CTR', type: 'aftermarket', price: 74, stock: 'in-stock', size: 'medium',
      fits: ['Honda Fit GK', 'Honda Vezel'] },
    { id: 'p-012', name: 'Steering Rack (Reconditioned)', category: 'suspension', sku: 'STR-RCK-PRD',
      brand: 'Toyota Genuine', type: 'used', price: 410, stock: 'order', size: 'large',
      fits: ['Toyota Prado 120', 'Toyota Hilux Vigo'] },
    { id: 'p-013', name: 'Stabiliser Link Set', category: 'suspension', sku: 'SUS-SLK-PRM',
      brand: '555', type: 'oem', price: 38, stock: 'in-stock', size: 'small',
      fits: ['Toyota Premio', 'Toyota Allion', 'Toyota Corolla'] },

    { id: 'p-014', name: 'Alternator 12V 100A', category: 'electrical', sku: 'ELE-ALT-2AZ',
      brand: 'Denso', type: 'oem', price: 230, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Noah', 'Toyota Ipsum', 'Toyota RAV4'] },
    { id: 'p-015', name: 'Starter Motor', category: 'electrical', sku: 'ELE-STR-1KD',
      brand: 'Denso', type: 'oem', price: 265, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Hilux', 'Toyota Prado'] },
    { id: 'p-016', name: 'Maintenance-Free Battery 70Ah', category: 'electrical', sku: 'ELE-BAT-70',
      brand: 'Panasonic', type: 'aftermarket', price: 118, stock: 'in-stock', size: 'medium',
      fits: ['Most petrol saloons and SUVs'] },
    { id: 'p-017', name: 'Oxygen (Lambda) Sensor', category: 'electrical', sku: 'ELE-O2-UNI',
      brand: 'Denso', type: 'oem', price: 79, stock: 'in-stock', size: 'small',
      fits: ['Toyota', 'Nissan', 'Honda petrol engines'] },
    { id: 'p-018', name: 'LED Headlamp Unit (Right)', category: 'electrical', sku: 'ELE-HDL-HRR',
      brand: 'Koito', type: 'genuine', price: 385, stock: 'order', size: 'medium',
      fits: ['Toyota Harrier 2018+'] },

    { id: 'p-019', name: 'Oil Filter', category: 'filters', sku: 'FLT-OIL-90915',
      brand: 'Toyota Genuine', type: 'genuine', price: 9, stock: 'in-stock', size: 'small',
      fits: ['Most Toyota petrol engines'] },
    { id: 'p-020', name: 'Air Filter Element', category: 'filters', sku: 'FLT-AIR-17801',
      brand: 'Toyota Genuine', type: 'genuine', price: 16, stock: 'in-stock', size: 'small',
      fits: ['Toyota Vitz', 'Toyota Axio', 'Toyota Probox'] },
    { id: 'p-021', name: 'Fuel Filter (Diesel, with Water Trap)', category: 'filters', sku: 'FLT-FUL-DSL',
      brand: 'Denso', type: 'oem', price: 34, stock: 'in-stock', size: 'small',
      fits: ['Toyota Hilux', 'Isuzu Elf', 'Mitsubishi Canter'] },
    { id: 'p-022', name: 'Full Service Kit (Oil, Air, Cabin, Plugs)', category: 'filters', sku: 'FLT-KIT-SRV',
      brand: 'Mixed OEM', type: 'oem', price: 78, stock: 'in-stock', size: 'small',
      fits: ['Toyota Corolla Axio', 'Toyota Premio', 'Toyota Fielder'],
      note: 'Everything needed for a 10,000 km service in one box.' },

    { id: 'p-023', name: 'Front Bumper (Unpainted)', category: 'body', sku: 'BDY-BMP-VTZ',
      brand: 'Aftermarket', type: 'aftermarket', price: 145, stock: 'in-stock', size: 'large',
      fits: ['Toyota Vitz 2015-2019'] },
    { id: 'p-024', name: 'Side Mirror Assembly (Power, Left)', category: 'body', sku: 'BDY-MIR-XT-L',
      brand: 'Nissan Genuine', type: 'genuine', price: 168, stock: 'in-stock', size: 'medium',
      fits: ['Nissan X-Trail T32'] },
    { id: 'p-025', name: 'Tail Lamp Assembly (Right)', category: 'body', sku: 'BDY-TL-HLX-R',
      brand: 'Depo', type: 'aftermarket', price: 88, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Hilux Revo'] },
    { id: 'p-026', name: 'Bonnet / Hood Panel', category: 'body', sku: 'BDY-BNT-AXIO',
      brand: 'Aftermarket', type: 'aftermarket', price: 210, stock: 'order', size: 'large',
      fits: ['Toyota Corolla Axio 2013-2018'] },
    { id: 'p-027', name: 'Wiper Blade Pair', category: 'body', sku: 'BDY-WPR-UNI',
      brand: 'NWB', type: 'oem', price: 22, stock: 'in-stock', size: 'small',
      fits: ['Universal fitment 14"–26"'] },

    { id: 'p-028', name: 'Tyre 265/65 R17 All-Terrain', category: 'tyres', sku: 'TYR-265-65-17',
      brand: 'Dunlop', type: 'aftermarket', price: 195, stock: 'in-stock', size: 'large',
      fits: ['Toyota Prado', 'Toyota Hilux', 'Ford Ranger'] },
    { id: 'p-029', name: 'Tyre 185/65 R15', category: 'tyres', sku: 'TYR-185-65-15',
      brand: 'Yokohama', type: 'aftermarket', price: 78, stock: 'in-stock', size: 'medium',
      fits: ['Toyota Axio', 'Honda Fit', 'Nissan Note'] },
    { id: 'p-030', name: 'Alloy Rim 17" (Each)', category: 'tyres', sku: 'RIM-ALY-17',
      brand: 'Japan Used', type: 'used', price: 130, stock: 'in-stock', size: 'large',
      fits: ['5x114.3 PCD vehicles'] },
    { id: 'p-031', name: 'Wheel Nut Set (20 pcs)', category: 'tyres', sku: 'RIM-NUT-20',
      brand: 'Aftermarket', type: 'aftermarket', price: 24, stock: 'in-stock', size: 'small',
      fits: ['M12 x 1.5 studs'] },

    { id: 'p-032', name: 'Automatic Gearbox (Reconditioned)', category: 'transmission', sku: 'TRN-ATM-1NZ',
      brand: 'Toyota Genuine', type: 'used', price: 980, stock: 'order', size: 'large',
      fits: ['Toyota Vitz', 'Toyota Axio', 'Toyota Sienta'],
      note: 'Fluid flushed, road tested, 3-month exchange warranty.' },
    { id: 'p-033', name: 'CV Joint Kit (Outer)', category: 'transmission', sku: 'TRN-CVJ-FIT',
      brand: 'GSP', type: 'aftermarket', price: 62, stock: 'in-stock', size: 'small',
      fits: ['Honda Fit', 'Honda Vezel', 'Honda Freed'] },
    { id: 'p-034', name: 'Propeller Shaft Centre Bearing', category: 'transmission', sku: 'TRN-PSB-HLX',
      brand: 'NTN', type: 'oem', price: 55, stock: 'in-stock', size: 'small',
      fits: ['Toyota Hilux', 'Toyota Hiace'] },
    { id: 'p-035', name: 'Rear Differential Assembly', category: 'transmission', sku: 'TRN-DIF-PRD',
      brand: 'Toyota Genuine', type: 'used', price: 720, stock: 'order', size: 'large',
      fits: ['Toyota Prado 120', 'Toyota Land Cruiser 100'] },
    { id: 'p-036', name: 'Engine Mount Set', category: 'transmission', sku: 'TRN-MNT-NOAH',
      brand: 'Tenneco', type: 'aftermarket', price: 96, stock: 'in-stock', size: 'small',
      fits: ['Toyota Noah', 'Toyota Voxy', 'Toyota Isis'] }
  ]
};
