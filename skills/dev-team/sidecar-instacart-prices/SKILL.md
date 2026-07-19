---
name: sidecar-instacart-prices
description: >
  Sidecar workflow for scraping Instacart grocery prices via Hermes stealth browser.
  Used by Crispi app to get real-time price comparisons across Arizona stores.
  Trigger: POST /api/sidecar/prices/scrape with items + zipCode.
triggers:
  - sidecar price scrape
  - instacart prices
  - grocery price comparison
  - shopping list prices
---

# Sidecar Instacart Price Scraping

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## CRITICAL: Browserbase, NOT Playwright

**Pitfall:** Instacart blocks regular Playwright/Puppeteer headless browsers.
The Hermes browser tool uses Browserbase stealth mode, which BYPASSES
Instacart's anti-bot detection. This was proven with a live test.

- ❌ Playwright standalone → gets blocked ("Page not found")
- ❌ Playwright with stealth args → gets blocked
- ❌ Puppeteer → gets blocked
- ✅ Hermes browser tool (Browserbase) → WORKS, got real prices live

**Bob's correction:** When asked "why use Playwright if Hermes browser works?"
the answer is: DON'T use Playwright. Use Hermes browser via the Sidecar.

## Architecture

The Sidecar IS Hermes. Hermes HAS the Browserbase stealth browser.
Therefore: Crispi → Sidecar route → Hermes browser → Instacart.

```
User taps "Compare Prices" in Crispi
    → POST /api/sidecar/prices/scrape { items, zipCode }
    → Sidecar route returns Instacart URLs + instructions
    → Hermes (Sidecar) processes using stealth browser:
        1. browser_navigate(url) for each Instacart search URL
        2. browser_snapshot(full=True) to read rendered page
        3. Parse prices from snapshot text
    → POST /api/sidecar/prices/store-results with scraped data
    → Crispi displays price comparison to user
```

**Why this works:** The Sidecar runs as Hermes on the same Railway
private network. It has access to the Browserbase stealth browser.
No API keys needed for Instacart scraping.

## Workflow

### Step 1: Receive Scrape Request

The Sidecar route returns:
```json
{
  "stores": [...],
  "urls": [
    { "item": "chicken breast", "store": "Safeway", "url": "https://www.instacart.com/store/search/chicken%20breast?zipcode=85001" }
  ],
  "instructions": "..."
}
```

### Step 2: Scrape Each URL

For each URL in the response:

1. `browser_navigate` to the URL
2. Wait for page to load (it uses stealth, so it works)
3. `browser_snapshot(full=true)` to get the full page content
4. Parse the snapshot for prices

### Step 3: Extract Prices from Snapshot

Look for these patterns in the snapshot text:
- `Current price: $X.XX` — the actual price
- `heading "Store Name"` — which store the price is from
- `/lb` — price per pound
- `/pkg` — price per package
- `loyalty card` — requires loyalty card for this price
- `BIG DEAL` or `Sale` — on sale

Example extraction:
```
Store: Fry's
Product: Heritage Farm® Boneless Skinless Chicken Breasts
Price: $2.99/lb
Loyalty: No

Store: Sprouts
Product: Sprouts Organic Thin-Sliced Chicken Breast
Price: $10.99/lb (or $10.66/pkg)
Loyalty: No
```

### Step 4: POST Results Back

After scraping all URLs, POST the results:

```bash
curl -X POST http://localhost:3000/api/sidecar/prices/store-results \
  -H "Authorization: Bearer $SIDECAR_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "itemName": "chicken breast",
        "storeName": "Safeway",
        "productName": "Heritage Farm Boneless Skinless",
        "price": 2.99,
        "unit": "lb",
        "loyaltyPrice": false
      }
    ]
  }'
```

## Arizona Stores (on Instacart)

| Store | Slug | Chain | Notes |
|-------|------|-------|-------|
| Fry's | frys-food-stores | Kroger | USE KROGER API INSTEAD |
| Safeway | safeway | Albertsons | Scrape via Instacart |
| Albertsons | albertsons | Albertsons | Scrape via Instacart |
| Bashas' | bashas | Bashas' | Scrape via Instacart |
| Sprouts | sprouts-farmers-market | Sprouts | Scrape via Instacart |
| Walmart | walmart | Walmart | USE WALMART API INSTEAD |
| Target | target | Target | Scrape via Instacart |
| Costco | costco | Costo | Scrape via Instacart |

## Rate Limiting

- Wait 1.5-2 seconds between URL scrapes
- Max 5 items per scrape request
- Max 6 stores per scrape (skip Fry's and Walmart if APIs available)

## Error Handling

- If Instacart returns "Page not found" — bot detected, skip that URL
- If prices not found in snapshot — log warning, continue
- If browser fails to launch — return error to Crispi

## Distance Filtering & ROI Analysis

### User Preferences (Onboarding)
During onboarding, ask:
1. "How far will you travel?" → `maxTravelDistance` (miles)
2. "Shopping style?" → `shoppingStrategy`:
   - `lowest_total` — price shop across multiple stores
   - `one_store` — buy everything at ONE store
   - `balanced` — balance price vs convenience

### Distance Filtering
Instacart shows distance for each store (e.g., "0.5 mi", "3.5 mi").
The scrape endpoint filters stores by `maxTravelDistance`:
```json
POST /api/sidecar/prices/scrape
{
  "items": ["chicken breast", "milk"],
  "zipCode": "85001",
  "maxTravelDistance": 5,
  "shoppingStrategy": "lowest_total"
}
```

### ROI Analysis
After scraping, call the analysis endpoint:
```json
POST /api/sidecar/prices/analyze
{
  "items": [
    { "itemName": "chicken breast", "storeName": "Safeway", "price": 2.99, "distanceMiles": 0.9 }
  ],
  "shoppingStrategy": "lowest_total",
  "gasPricePerGallon": 3.50,
  "vehicleMpg": 25,
  "deliveryPreferences": {
    "hasInstacartPlus": false,
    "hasWalmartPlus": true
  }
}
```

Response includes:
- Total cost per store (food + gas round trip)
- Travel time per store
- Best store recommendation
- Savings vs most expensive store
- Delivery vs driving comparison per store

### Delivery Cost Comparison (NEW)
The ROI analysis now compares DRIVING vs DELIVERY for each store.

**Driving cost:** food + gas (round trip)
**Delivery cost:** food + delivery fee + service fee

Recommends the cheapest option. If user has Instacart+, delivery
is often cheaper than driving for nearby stores.

Example output:
```
RECOMMENDATION: Safeway
  → DELIVER via Instacart
  Total cost: $6.48
  (driving would cost $6.73 — delivery saves $0.25)

DELIVERY OPTIONS (cheaper than driving):
  Safeway: $6.48 via Instacart (saves $0.25 vs driving)
  Walmart: $7.50 via Walmart+ (saves $0.78 vs driving)
```

**Delivery fee defaults (no subscription):**
- Instacart stores: $3.99 delivery + 5% service fee
- Walmart: $0 (Walmart+)
- Free delivery thresholds: $35 (most), $75 (Costco)

### ROI Calculation
```
gas_cost = (distance × 2 / mpg) × gas_price_per_gallon
travel_time = (distance × 2 / avg_speed_mph) × 60
total_cost = food_cost + gas_cost
```

### Store Distances (Phoenix 85001 approximate)
| Store | Distance | Notes |
|-------|----------|-------|
| Fry's | 0.5 mi | Use Kroger API instead |
| Safeway | 0.9 mi | Scrape via Instacart |
| Albertsons | 1.2 mi | Scrape via Instacart |
| Bashas' | 1.5 mi | Scrape via Instacart |
| Target | 2.0 mi | Scrape via Instacart |
| Walmart | 2.8 mi | Use Walmart API instead |
| Sprouts | 3.5 mi | Scrape via Instacart |
| Costco | 4.2 mi | Scrape via Instacart |

## Testing

Run the test script to verify the workflow:
```bash
cd /media/bob/C/AI_Projects/Crispi-app
node --test src/server/__tests__/sidecarPriceScraping.test.ts
```
