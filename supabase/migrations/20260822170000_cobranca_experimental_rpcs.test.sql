do $$
declare r jsonb;
begin
  -- forma: sempre {ok, linhas}, linhas nunca null
  r := public.fn_experimental_lembrete_alvos(20);
  if (r->>'ok')::boolean is not true or jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 1: forma errada em lembrete_alvos: %', r;
  end if;

  r := public.fn_experimental_pendencia_do_professor(-1);
  if jsonb_array_length(r->'linhas') <> 0 then
    raise exception 'FALHOU 2: professor inexistente devia vir vazio, veio %', r;
  end if;

  r := public.fn_experimental_escalonadas();
  if jsonb_typeof(r->'linhas') <> 'array' then
    raise exception 'FALHOU 3: escalonadas devia ser array, veio %', jsonb_typeof(r->'linhas');
  end if;

  -- janela: nada com menos dias que a janela pode aparecer no escalonamento
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_escalonadas()->'linhas') x
     where (x->>'dias_em_atraso')::int < public.fn_janela_experimental_dias()
  ) then
    raise exception 'FALHOU 4: escalonamento trouxe caso dentro da janela';
  end if;

  -- lembrete: janela de minutos é respeitada
  if exists (
    select 1 from jsonb_array_elements(public.fn_experimental_lembrete_alvos(20)->'linhas') x
     where (x->>'horas_em_atraso')::int > 1
  ) then
    raise exception 'FALHOU 5: lembrete trouxe aula de mais de 1h atras com janela de 20min';
  end if;

  raise exception 'VERDE: RPCs ok';
end $$;
