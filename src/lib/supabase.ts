import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY;
function validateConfiguration() {
  if (!url || !key) {
    return 'Supabase is not configured for this deployment. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in Vercel, then redeploy.';
  }

  try {
    const parsed = new URL(url);
    const localDevelopment = parsed.hostname === 'localhost' || parsed.hostname === '127.0.0.1';
    if ((!localDevelopment && parsed.protocol !== 'https:') || /your-project|placeholder/i.test(parsed.hostname)) {
      return 'VITE_SUPABASE_URL is still a placeholder. Replace it with your Supabase project URL and redeploy.';
    }
  } catch {
    return 'VITE_SUPABASE_URL is not a valid URL. Copy the Project URL from your Supabase project settings.';
  }

  if (key.length < 20 || /your-supabase|placeholder/i.test(key)) {
    return 'VITE_SUPABASE_ANON_KEY is still a placeholder. Replace it with the project’s anon or publishable key and redeploy.';
  }

  return '';
}

export const supabaseConfigError = validateConfiguration();
export const isConfigured = !supabaseConfigError;
export const supabase = createClient(url || 'https://placeholder.supabase.co', key || 'placeholder-anon-key');

export function friendlySupabaseError(error: unknown) {
  if (error instanceof Error && /failed to fetch|network request failed|fetch failed/i.test(error.message)) {
    return 'QuickCart could not reach Supabase. Check that VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY are correct and belong to the same project, then redeploy.';
  }
  return error instanceof Error ? error.message : 'We couldn’t complete that. Please try again.';
}
