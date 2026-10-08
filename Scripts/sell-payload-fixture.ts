/**
 * Writes RewatchTests/Fixtures/sell-listing-payload.json: the listing body the
 * WEBSITE's builder sends for a handful of answers, computed by the site's own
 * code (`builderListingPayload` in listingBuilderModel.ts, which goes through
 * the shared `sellListingPayload`). The iOS test (`SellListingPayloadParityTests`)
 * maps the same answers through the app's builder and requires the same JSON,
 * key for key and value for value.
 *
 * Run it from the frontend checkout so its path aliases resolve:
 *
 *   cd ../frontend && npx vite-node --config vitest.config.ts \
 *     ../ios/Scripts/sell-payload-fixture.ts
 *
 * Re-run it whenever either side changes what it sends; a diff in the fixture
 * is the drift this exists to catch.
 */
import { writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { EMPTY, builderListingPayload, type Answers } from "@/pages/account/sell/listingBuilderModel";

type Case = { name: string; needsCustomsFields: boolean; answers: Partial<Answers> };

const cases: Case[] = [
  {
    name: "matched watch, parts differ, notes everywhere, replaced and serviced, 48-hour returns, Vault link",
    needsCustomsFields: false,
    answers: {
      brand: " Rolex ",
      model: "Submariner  Date",
      reference: "126610LN",
      year: "2021",
      sku: " A-1042 ",
      grade: "Very Good",
      partsMatch: false,
      parts: {
        case: "Good",
        dial: "Like New",
        bezel: "Very Good",
        crystal: "Very Good",
        bracelet: "Good",
        clasp: "Very Good",
        caseback: "Very Good",
      },
      conditionNotes: {
        overall: "Worn gently,  never polished",
        case: " Light desk marks on the lugs ",
        bracelet: "Slight stretch,\nall links",
        crystal: "   ",
      },
      box: { box: true, papers: true, booklets: false },
      notes: " Comes with an extra strap. ",
      history: { polish: "polished", originality: "replaced", serviceHistory: "serviced" },
      replaced: " the crown   and the crystal ",
      serviceYear: "2023",
      priceText: "12,450.50",
      price: 12450.5,
      returns: "48",
      vaultMatch: {
        vault_watch_id: "7d1c2f0e-5b7a-4c1e-9a43-2f6a1d0b9c11",
        brand: "Rolex",
        model: "Submariner Date",
        reference: "126610LN",
        acquired_date: "2024-03-02",
        passport_code: null,
      },
    },
  },
  {
    name: "all parts match, year unknown, no returns, watch only, stale part note and follow-ups not sent",
    needsCustomsFields: false,
    answers: {
      brand: "Omega",
      model: "Speedmaster Professional",
      reference: "310.30.42.50.01.001",
      year: "unknown",
      sku: "",
      grade: "New",
      partsMatch: true,
      parts: {},
      conditionNotes: { overall: "", dial: "a note from before the seller said every part matches" },
      box: { box: false, papers: false, booklets: false },
      notes: "",
      history: { polish: "unknown", originality: "all_original", serviceHistory: "never" },
      replaced: "left over from Some parts replaced",
      serviceYear: "2019",
      priceText: "100",
      price: 100,
      returns: "none",
    },
  },
  {
    name: "a dealer outside the US: customs details, 72-hour returns, replaced and serviced with nothing typed",
    needsCustomsFields: true,
    answers: {
      brand: "Tudor",
      model: "Black Bay 58",
      reference: "79030N",
      year: "2019",
      sku: "TB-58",
      grade: "Like New",
      partsMatch: true,
      parts: {},
      conditionNotes: { overall: "Barely worn" },
      box: { box: true, papers: false, booklets: true },
      notes: "Full kit.\nSecond line of notes.",
      history: { polish: "unpolished", originality: "replaced", serviceHistory: "serviced" },
      replaced: "",
      serviceYear: "",
      priceText: "3,450",
      price: 3450,
      returns: "72",
      customs: { country: "ch", hts: " 9102.11 " },
    },
  },
];

const out = cases.map(({ name, needsCustomsFields, answers }) => {
  const full: Answers = { ...EMPTY, ...answers };
  return {
    name,
    needsCustomsFields,
    answers: {
      brand: full.brand,
      model: full.model,
      reference: full.reference,
      year: full.year,
      sku: full.sku,
      grade: full.grade,
      partsMatch: full.partsMatch,
      parts: full.parts,
      conditionNotes: full.conditionNotes,
      box: full.box,
      notes: full.notes,
      history: full.history,
      replaced: full.replaced,
      serviceYear: full.serviceYear,
      priceText: full.priceText,
      returns: full.returns,
      customs: full.customs,
      vaultWatchId: full.vaultMatch?.vault_watch_id ?? null,
    },
    // JSON.stringify drops undefined keys exactly as the request does.
    expected: JSON.parse(JSON.stringify(builderListingPayload(full, { needsCustomsFields }))),
  };
});

const here = dirname(fileURLToPath(import.meta.url));
const target = resolve(here, "../RewatchTests/Fixtures/sell-listing-payload.json");
writeFileSync(target, `${JSON.stringify(out, null, 2)}\n`);
console.log(`wrote ${out.length} cases to ${target}`);
