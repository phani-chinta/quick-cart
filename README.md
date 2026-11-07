# QuickCart

QuickCart is a considered everyday essentials shop for India. This repository contains a responsive React storefront backed by Supabase Auth and PostgreSQL, persistent per-user carts, and an atomic Cash on Delivery checkout.

## Features

- Responsive homepage, category catalogue, product search and price sorting
- Supabase email/password signup, sign in, confirmation, recovery and password reset
- PostgreSQL backed cart with ownership policies and stock-aware quantities
- Checkout RPC that locks stock, verifies live prices, creates order snapshots, decrements inventory, and clears the cart in one transaction
- Private order history and account profile
- Accessible labels, visible keyboard focus, reduced-motion support, lazy product images

## Stack

React, Vite, TypeScript, React Router, Tailwind CSS, Framer Motion, Lucide, React Hook Form, Zod, Supabase, PostgreSQL.

## Local setup

1. Install Node.js 20.19+ or 22.12+.
2. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` from the Supabase project's public API settings. The anon key is designed for client use; never put a service-role key in a Vite variable.
3. Run `supabase/migrations/001_initial_schema.sql` in the Supabase SQL Editor, or apply it with the Supabase CLI (`supabase db push`). It creates the schema, triggers, RLS policies, atomic checkout RPC, and 18 sample products across five categories.
4. In Supabase Authentication settings, enable email/password and set the Site URL to your local URL. Add `http://localhost:5173/profile` and `http://localhost:5173/reset-password` as redirect URLs.
5. Run `npm install`, `npm run dev`, then open the URL printed by Vite.

Without valid Supabase environment variables (including untouched example placeholders) the UI starts in disconnected mode, explains which setting is wrong, and blocks auth requests instead of showing a fetch failure. Authentication, catalogue data, cart and checkout require a connected project. The `/setup` route describes the same setup steps.

## Security and data model

Every user-owned table enables RLS. Profile and cart policies are scoped to `auth.uid()`. Orders and their line items are readable only by their owner. Product and order financial fields have no customer write policies. The checkout RPC is an invoker function with a restricted search path and authenticated-only execute grant. It recalculates totals from database prices and locks product rows before stock validation and update.

Tables: `profiles`, `categories`, `products`, `cart_items`, `orders`, `order_items`.

## Production / Vercel

- Import the repository into Vercel and add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in project environment variables for Preview and Production. These exact `VITE_` names are read by Vite at build time. Use the Project URL and anon/publishable key from the same Supabase project; do not use the service-role key. Redeploy after changing variables because Vite embeds them into the build.
- Configure the production domain as the Supabase Auth Site URL and allow `/profile` and `/reset-password` redirect URLs on that domain.
- Apply migrations to the production Supabase database before serving traffic.
- `vercel.json` rewrites client routes to the SPA entry point so nested URLs survive refresh.
- Run `npm run build` for the TypeScript check and production bundle; `npm run preview` serves the built site locally.

## Project map

`src/context` owns session and cart state; `src/lib` initializes the Supabase client; `src/App.tsx` composes routes and page components; `src/types` contains shared models; `supabase/migrations` is the database source of truth.
