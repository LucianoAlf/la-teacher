import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type FabioAudioRow = {
  id: string;
  aula_id: number;
  professor_id: number | null;
  unidade_id: string;
  storage_path: string;
  status: string;
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function assinarHMAC(secret: string, payload: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function marcarErro(supabase: ReturnType<typeof createClient>, audioId: string, erro: string) {
  await supabase
    .from("fabio_fila_audios")
    .update({ status: "erro", erro: erro.slice(0, 500), atualizado_em: new Date().toISOString() })
    .eq("id", audioId);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  try {
    const { audio_id } = await req.json().catch(() => ({}));
    if (!audio_id) {
      return json({ error: "audio_id obrigatório" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const webhookUrl = Deno.env.get("FABIO_WEBHOOK_URL");
    const webhookSecret = Deno.env.get("FABIO_WEBHOOK_SECRET");

    if (!supabaseUrl || !serviceRole || !webhookUrl || !webhookSecret) {
      return json({ error: "edge secrets incompletos" }, 500);
    }

    const supabase = createClient(supabaseUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: audio, error: eAudio } = await supabase
      .from("fabio_fila_audios")
      .select("id, aula_id, professor_id, unidade_id, storage_path, status")
      .eq("id", audio_id)
      .single<FabioAudioRow>();

    if (eAudio || !audio) {
      return json({ error: "áudio não encontrado" }, 404);
    }

    if (!["pendente", "erro"].includes(audio.status)) {
      return json({ status: "ignorado", motivo: `status ${audio.status}` }, 200);
    }

    const { data: signed, error: eSigned } = await supabase
      .storage
      .from("fabio-audios")
      .createSignedUrl(audio.storage_path, 600);

    if (eSigned || !signed?.signedUrl) {
      await marcarErro(supabase, audio.id, "falha ao gerar signed url");
      return json({ error: "falha signed url" }, 500);
    }

    const { data: reg } = await supabase
      .from("fabio_registros_aula")
      .select("id")
      .eq("audio_id", audio.id)
      .is("parent_id", null)
      .maybeSingle<{ id: string }>();

    const payload = {
      audio_id: audio.id,
      aula_id: audio.aula_id,
      unidade_id: audio.unidade_id,
      professor_id: audio.professor_id,
      audio_url: signed.signedUrl,
      registro_id: reg?.id ?? null,
    };

    const body = JSON.stringify(payload);
    const signature = await assinarHMAC(webhookSecret, body);

    const { error: eUpdate } = await supabase
      .from("fabio_fila_audios")
      .update({ status: "transcrevendo", atualizado_em: new Date().toISOString(), erro: null })
      .eq("id", audio.id)
      .in("status", ["pendente", "erro"]);

    if (eUpdate) {
      return json({ error: "falha ao atualizar fila", detalhe: eUpdate.message }, 500);
    }

    const resp = await fetch(webhookUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Signature": signature,
      },
      body,
    });

    if (!resp.ok) {
      const txt = await resp.text();
      await marcarErro(supabase, audio.id, `hermes ${resp.status}: ${txt}`);
      return json({ error: "hermes recusou", status: resp.status, detalhe: txt }, 502);
    }

    return json({ status: "enviado_ao_fabio", audio_id: audio.id }, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
