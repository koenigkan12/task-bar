# Contratos entre módulos — *Quantos Dias?* (Godot 4.6, GDScript)

Documento técnico para quem constrói o jogo em paralelo. **É a fonte de verdade das interfaces.** Se o seu módulo precisar mudar uma interface, mude o código **e este documento** (só a sua seção) e avise no relatório final.
Design: ver `docs/analise-de-design.md` (decisões já tomadas) e o conceito original do autor (resumido na seção 1).

---

## 0. Regras para quem trabalha nisto

- Idioma: texto visível ao jogador sempre via `I18n` (chaves), em **PT-BR e EN**. Comentários de código em português, curtos. Identificadores em inglês, `snake_case`.
- GDScript **tipado** (`var x: int`, `-> void`). Um `class_name` por script reutilizável. Sem `await` no `_ready()` de autoloads.
- Todo número de balanceamento mora em `data/balance.json` (nunca espalhar constantes).
- **Não faça commit nem push.** Quem integra é o orquestrador.
- **Trabalhe numa cópia privada** (vários módulos são feitos ao mesmo tempo e o cache `.godot/` não aguenta dois Godot no mesmo diretório):
  ```
  mkdir -p /home/claude/work && cp -r /home/claude/task-bar /home/claude/work/<seu_nome>
  # desenvolva e teste lá; no fim, copie SÓ os arquivos do seu módulo de volta para /home/claude/task-bar
  ```
  Se precisar de algo de outro módulo que ainda não existe, escreva um **stub local** (não o copie de volta).
- Godot: `/home/claude/tools/godot/Godot_v4.6-stable_linux.x86_64`.
  - Teste lógico: `godot --headless --path <projeto> --script res://tests/xxx.gd` (script `extends SceneTree`; autoloads são acessados por `root.get_node("/root/Game")`; prefira testar classes puras `Sim`, `Balance`).
  - Captura de tela (renderiza de verdade com Mesa/llvmpipe): `xvfb-run -a -s "-screen 0 1280x720x24" godot --path <projeto> --rendering-driver opengl3 ...` e salve com `get_viewport().get_texture().get_image().save_png(...)`. Depois **olhe a imagem** (ferramenta Read abre PNG).
  - Importação de assets novos: `godot --headless --path <projeto> --import` (rode antes de usar PNG/áudio novos).
- Não chame ferramentas `mcp__hearthbot__*`. Arquivos temporários: use o scratchpad da sessão, não `/tmp`.
- Relatório final (≤ 200 palavras): o que fez, arquivos entregues, desvios deste contrato, o que **não** conseguiu verificar.

## 1. O jogo em dez linhas

Idle cozy numa janela baixa grudada no rodapé da tela (corte de terra de um bunker). Um homem sozinho depois do fim do mundo; a esposa ficou lá fora. Ele planta, constrói gambiarras de sucata para automatizar a vida e melhora a antena do rádio; cada nível de antena traz uma voz nova (história) e libera máquinas. Tudo vem de dentro do bunker, nada de personagens novos, sem morte, sem punição. A esposa nunca aparece: só voz/texto no rádio. Ela chega **fora da tela** depois de o jogador "preparar a casa" (lista de 6 itens); aí o jogo vira epílogo contínuo. Tom: pé no chão, emotivo, cozy. Duração: ~14 dias de relógio até a antena 5. Ritmo: números em escala humana (dezenas e centenas), sem explosão.

Decisões da análise de design já valem: janela opaca que cresce ao escavar; **gaveta** que cresce para cima nos check-ins; plantar é **configuração permanente do vaso**; progresso **offline** pelo mesmo código; **Diário do rádio**; rádio **programada** por horário real; sem som por padrão até a primeira interação; 3 modos de áudio (silencioso, ambiente, completo); sinais de atenção sem nag; mover/desmontar de graça (devolve 100%).

Descartado (não reproponha): roguelike com morte, espelhar a vida do jogador (timers de foco), expedições, robôs, visitantes com história, filha no bunker, clima, humor, prestígio.

---

## 2. Estrutura de pastas e responsáveis

```
project.godot
data/balance.json            (orquestrador; sim ajusta números se o teste de ritmo pedir)
data/radio.json              (conteúdo)
data/journey.json            (conteúdo)
data/i18n/strings_*.csv      (cada módulo é dono do seu csv; ver seção 6)
scripts/sim/                 Sim, Balance, Game (autoload), Save           [SIM]
scripts/platform/            Settings, WindowService (autoloads)            [PLATAFORMA]
scripts/i18n/                I18n (autoload)                                [CONTEÚDO]
scripts/audio/               AudioManager (autoload)                        [ÁUDIO]
scripts/view/ scenes/bunker/ cena do bunker e personagem                    [VIEW]
scripts/ui/ scenes/ui/       gaveta, título, opções, balões                 [UI]
scenes/main.tscn             fluxo principal                                [orquestrador]
assets/art/env, assets/art/man, assets/art/manifest_*.json                  [ARTE-AMBIENTE / ARTE-PERSONAGEM]
assets/audio/**              ogg gerados + default_bus_layout               [ÁUDIO]
assets/fonts/                fonte pixel + licença                          [UI]
tools/art, tools/audio, tools/sim_oracle   geradores Python (tools/.gdignore)
tests/                       testes headless                                [cada módulo: tests/<modulo>_*.gd]
```

Autoloads (ordem em `project.godot`): `Settings`, `I18n`, `Game`, `WindowService`, `AudioManager`. Já existem **stubs vazios** (`extends Node`) em cada caminho; o módulo dono substitui pelo real.

---

## 3. Geometria e coordenadas (pixels lógicos)

- Tile = 16 px. **Escala inteira** (×1..×4) aplicada pelo Godot (`stretch mode = viewport`, `scale_mode = integer`). Tudo é desenhado em coordenadas lógicas.
- Altura da faixa: **136 px com 1 sala** (`BunkerGeo.H`; `BunkerGeo.height(n)` = 136 + 51·(n−1), ou seja 187 com 2 salas e 238 com 3) = superfície 32 (céu y 0–24 + grama y 24–32) + andar de cima (A, y 32–85) + laje + andar de baixo (B, y 85–136). Direção de arte aprovada em 13/10/2026 (lateral com cômodos de verdade, 2 andares): `docs/direcao-de-arte-comodos.md`.
- Sala (andar A): largura interna **192 px = 12 colunas de 16 px**. Teto y 32–40 (8 px); parede do fundo y 40–80; piso y 80–85 (5 px visíveis). O andar B repete a geometria deslocada de `FLOOR_DY = 51` (teto 85–91, parede 91–131, pés `FEET_Y_B = 131`, piso 131–136). O andar B é a **despensa** (fixa, não recebe itens): o estoque aparece nas prateleiras (`PantryStock`). **Salas novas são cavadas PARA BAIXO**: a sala 2 fica no andar C e a sala 3 no andar D (`BunkerGeo.floor_dy(room)` = 0 / 102 / 153; `feet_y(room)`, `wall_y(room)`, `room_y(room)`), todas com x0 = 8 e o poço da escada na coluna 0 (`rooms.fixed.N` traz o `ladder`). **Linha dos pés = y 80.** Objetos de 1 tile têm topo em y 64; de 2 tiles, topo y 48. Personagem 32×32, pés em y 80 (topo y 48).
- Salas: todas começam em `x = 8` (uma por andar: A, C, D); parede grossa de concreto de 8 px em `x = 200` fechando cada sala à direita (não há porta lateral: a ligação é o poço da escada, coluna 0). Cada sala tem seu material: sala 1 concreto com luz quente (mapa, calendário, quadro de ferramentas, cantinho de dormir com lambri), sala 2 azulejo claro com luz de cultivo (esverdeada), sala 3 lambri de madeira e piso de tábua. Canos e fios correm no teto de cada andar. Margem de terra de 8 px à esquerda.
- Largura lógica da faixa: **208 px** sempre (`BunkerGeo.strip_width()`), porque os andares são empilhados e não lado a lado. **O que não foi escavado é terra maciça** (mesmos tiles de terra), então a janela pode ser mais larga que as salas (mínimo da gaveta, abaixo). A janela cresce para cima quando uma escavação começa (`Main._strip_h()`).
- Gaveta: ao abrir, a janela cresce **para cima**: altura lógica total = altura da faixa + `DRAWER_H` (120) = **256** com 1 sala; largura = `max(208, 344)`. Ao fechar, volta à altura da faixa (`Drawer.set_strip_height`).
- Tela de título: usa o tamanho da gaveta aberta (344×256 mínimo).
- Escotilha/escada: coluna 0 da sala 1 (x 8–24). A escada sobe do chão até a superfície; a tampa da escotilha (`hatch`) fica sobre a grama em `x = 8..40`. A caixa da escotilha (`hatch_box`) fica na coluna 1 da sala 1. Mesa do rádio na coluna 2. Cama (`bed`, 2 colunas) nas colunas 10–11.
- Antena (`antenna_N`, 24×24) fica na superfície com a base em y = 24 (topo da grama), x ≈ 56; painel solar (`painel`) na superfície à direita do mastro. O céu muda de cor com a hora (tint por código).
- Luz do relógio: um cone de luz (degradê aditivo por código) desce pelo poço da escada: dia = claro, noite = quase nada.
- Andar B (cenário, sem itens do jogador): despensa sob a sala 1 (prateleiras com latas, caixas etiquetadas, cisterna, porta de aço) e, quando a sala 2 existe, uma escavação com escoras de madeira sob ela; sob o resto, terra com pedra, raiz e cano enterrado. A escavação real de salas continua para o lado. A escada do poço desce até o andar B. Lâmpadas: `BunkerGeo.lamp_points(n)`.
- Colunas livres da sala 1: 3–9 (7 colunas). Salas 2 e 3: colunas 0–11 livres.

---

## 4. Autoloads e APIs

### 4.1 `Settings` (scripts/platform/settings.gd) [PLATAFORMA]
Persistência em `user://settings.json`, escrita com atraso (debounce 0,5 s) e atômica (arquivo temporário + rename).
```gdscript
signal changed(key: String)
func get_value(key: String, default: Variant = null) -> Variant
func set_value(key: String, value: Variant) -> void
# extras: has_value(key), flush() -> bool (grava já), reset_all(), reload(path := "")
```
Valores com tipo errado/fora da faixa voltam ao padrão (ui_scale: "auto"|1..4, volume 0..1); chaves desconhecidas são preservadas; JSON corrompido vira `settings.json.bad`. `set_value` só emite `changed` se o valor mudou. Chaves e padrões: `locale` ("auto"), `audio_mode` ("ambient"; "silent"|"ambient"|"full"), `master_volume` (0.8), `ui_scale` ("auto"|1|2|3|4), `always_on_top` (false), `energy_mode` ("auto"; "auto"|"low"|"normal"), `window_pos` (Dictionary por monitor), `anchor` ("bottom_left"), `text_size` (1.0), `reduce_flicker` (false), `first_run_done` (false), `tray_enabled` (true), `autostart_hint_seen` (false), `sound_unlocked` (false; vira true na primeira interação).

### 4.2 `I18n` (scripts/i18n/i18n.gd) [CONTEÚDO]
```gdscript
signal locale_changed(code: String)
var locale: String            # "pt_BR" | "en"
func t(key: String, args: Dictionary = {}) -> String   # substitui {nome} por args["nome"]; chave ausente => devolve a própria chave
func set_locale(code: String) -> void
func has_key(key: String) -> bool
```
Lê todos os `res://data/i18n/strings_*.csv` em runtime (cabeçalho `key,pt_BR,en`, aspas CSV padrão, `\n` literal vira quebra de linha). `locale = "auto"` usa `OS.get_locale_language()` (pt → pt_BR, resto → en).
- Implementação: parser puro em `scripts/i18n/i18n_csv.gd` (`class_name I18nCsv`). Lista de arquivos = `_index.json` ∪ varredura da pasta. Valor vazio em `en` cai para `pt_BR`; chave ausente devolve a chave (aviso uma vez). `set_locale()` aceita `auto|pt|pt_BR|en|en_US…` e grava em `Settings`; reage também a `Settings.changed("locale")`. Extra: `available_locales()`, `reload()`.
- **Export:** o Godot não empacota `.csv` cru (vira tradução). Cada CSV tem um `.csv.import` com `importer="keep"` e existe `data/i18n/_index.json`. **Ao criar/remover um `strings_*.csv`, rode `python3 tools/content/make_i18n_index.py`.** Conferência de chaves: `python3 tools/content/check_strings.py`.

### 4.3 `Sim` / `Balance` / `Game` (scripts/sim/) [SIM]
- `class_name Balance`: carrega `data/balance.json`, `radio.json`, `journey.json`; getters tipados (`Balance.item(id)`, etc.). `Balance.load_all(path_prefix := "res://data/")`.
- `class_name Sim extends RefCounted`: **toda a lógica**, sem nós, sem relógio de parede: `advance(game_minutes: float)` avança em passos de `balance.time.step_min`. Determinística. Emite sinais (Sim tem os mesmos sinais de `Game`, que apenas os repassa).
- `Game` (autoload, `extends Node`): dono de uma `Sim`; liga o relógio de parede (`_process` acumula `delta * time_scale / 60` minutos de jogo, em passos), faz catch-up offline ao carregar (`last_seen_unix`), autosave (a cada 60 s, ao perder foco, ao sair), repassa sinais. Opção de linha de comando `--demo` (time_scale 6) e `--time-scale=<x>`.

Modelo (resumo; detalhes no código e em `tools/sim_oracle/economia_sim.py`, que é o oráculo):
- Cada vaso/plot tem `progress` (0..1) que avança `step/cycle_min × labor_factor` quando ele está acordado (06–22h de relógio do jogo); ao chegar a 1 colhe 1 cesto (soma ao estoque da caixa) e replanta sozinho (**ordem permanente**: o plot guarda a cultura).
- `labor_factor = min(1, tempo_disponível / tempo_exigido)` (o tempo do homem é o recurso escondido). Tarefas por ciclo por plot: plantar+colher, regar (zero se coberto pela irrigação automática), carregar (depende do transporte e do fator da sala do plot, `carry_room_factor`). Pedalar enquanto o gerador for a bicicleta. Obras consomem parte do tempo (`build_labor_share`).
- Caixa da escotilha: estoque em cestos; `visits_per_day[antena]` visitas igualmente espaçadas no período acordado; cada visita vende `min(estoque, capacidade)` pelo preço médio e soma sucata; excedente acima de `box_overflow_factor × capacidade` é perdido. Ele come `eat_per_day` por dia; sem comida a velocidade cai até `hunger_speed_floor` (nunca zero).
- Energia: compra checa `oferta >= demanda + necessidade`; não há liga/desliga. Demanda = rádio(nível) + lâmpadas(salas) + itens com `power`.
- Antena: sobe se `supply >= max(supply_min, demanda+headroom)`, salas ≥ requisito, sucata ≥ custo.
- Substituição de linha: itens com `replaces_line` substituem a instância anterior da linha (que some sem reembolso; a nova ocupa a posição, e a checagem de colunas livres considera a antiga já removida). Demolir qualquer outro item devolve 100%.
- Obras: comprar cria um *job* (`build_min = build_base_min + cost/build_cost_divisor`); o item aparece como "em obra" e fica pronto quando o job termina.
- Rádio: ver seção 5.1. Jornada pós-contato: ver 5.2.
- Offline: `Game` calcula `elapsed = now - last_seen` (limitado a `offline_cap_hours`, em horas de jogo), chama `sim.advance()` em blocos e emite `welcome_back(summary)` com `{hours, visits, scrap, harvested, nights, lines: Array[String], capped}` + uma entrada `away` no diário.

Sinais (`Game`):
```gdscript
signal state_changed()                                # no máx. 4x/s quando algo mudou
signal item_placed(instance_id: int)                  # compra confirmada; obra começou
signal item_finished(instance_id: int, item_id: String)
signal item_removed(instance_id: int)
signal room_dug(room: int)
signal antenna_changed(level: int)
signal radio_line(line: Dictionary)                   # {id, speaker, text_key, cue, kind, level, at_min}
signal diary_changed()
signal visit_happened(info: Dictionary)               # {units, scrap, box_after}
signal plot_harvested(plot_id: int)
signal box_state_changed(fill: float, overflow: bool)
signal welcome_back(summary: Dictionary)
signal house_item_bought(item_id: String)
signal arrival_started()                              # dispara a cena do final
signal arrival_finished()                             # entra em modo epílogo
signal new_game_started()
signal game_loaded()
```

API de consulta/comando (`Game`; `Sim` tem os mesmos métodos):
```gdscript
# ciclo de vida
func has_save() -> bool
func new_game() -> void
func load_game() -> bool
func save_game() -> void
func delete_save() -> void
var in_game: bool

# estado geral
func sucata() -> int
func antenna() -> int                 # 1..5
func rooms() -> int                   # 1..3
func tod_hours() -> float             # 0..24, hora do dia do jogo
func day_index() -> int               # dias desde o início (0 = primeiro dia)
func is_awake() -> bool
func is_night() -> bool
func busy() -> float                  # 0..1 fração do tempo dele ocupada com tarefas
func hungry() -> bool
func power_supply() -> int
func power_demand() -> int
func power_ok() -> bool
func box_stock() -> float
func box_capacity() -> int
func box_fill() -> float              # estoque/capacidade (pode passar de 1)
func contact_made() -> bool           # antena 5 alcançada
func arrived() -> bool                # ela chegou (epílogo)
func stats() -> Dictionary

# mundo (para a cena)
func instances() -> Array[Dictionary]     # {id,item,room,col,cols,state:"building"|"ready",build_ratio}
func fixed_objects(room: int) -> Array[Dictionary]   # {id,col,cols} (ladder, hatch_box, radio_table, bed)
func plots() -> Array[Dictionary]         # {id,instance,index,room,crop,progress,stage(0..3),ready,greenhouse}
func active_jobs() -> Array[Dictionary]   # {instance,item,ratio}
func unlocked_behaviors() -> Array[String]  # "ler","cochilar","ouvir_radio","escrever","olhar_foto"
func line_tiers() -> Dictionary           # {plantio:n, agua:"gotejador", energia:"moinho", transporte:"calha"}

# comandos
func catalog(filter: String = "") -> Array[Dictionary]  # filter: "", "plantio","agua","energia","transporte","decor","casa","escavacao"
   # entrada: {item,name_key,desc_key,cost,cols,line,tier,status:"available"|"locked"|"unaffordable"|"maxed"|"owned",
   #           missing:Array[String] (chaves i18n legíveis), pra_que:Array[String], post_contact:bool, pinned:bool}
func can_place(item_id: String, room: int, col: int) -> bool
func placement_hints(item_id: String) -> Array[Dictionary]   # [{room,col}] posições válidas (primeira coluna do bloco)
func can_buy(item_id: String, room: int = 0, col: int = -1) -> Dictionary    # {ok, missing:[...]}
func buy(item_id: String, room: int, col: int) -> Dictionary                 # {ok, instance_id, reason}
func dig_room() -> Dictionary                                                 # compra comodo2/comodo3
func antenna_info() -> Dictionary                                             # {level,next_cost,can,missing:[...],max:bool}
func upgrade_antenna() -> Dictionary                                          # {ok, reason}
func demolish(instance_id: int) -> Dictionary
func move(instance_id: int, room: int, col: int) -> Dictionary
func available_crops(instance_id: int) -> Array[String]
func set_instance_crop(instance_id: int, crop: String) -> void   # ordem permanente para todos os plots da estrutura
func pin_goal(item_id: String) -> void        # "" limpa
func pinned_goal() -> String
func goal_ready() -> bool                     # objetivo fixado está pago e liberado
func diary() -> Array[Dictionary]             # {id,kind:"radio"|"her"|"note"|"away"|"system",key,args,at_min,tod,day,read,while_away,speaker,cue}
func unread_count() -> int
func mark_diary_read() -> void
func house_status() -> Array[Dictionary]      # [{item,bought}] na ordem de journey.house_items
func journey() -> Dictionary                  # {contact_min,arrival_due_min,days_left,items_done,items_total}
# testes/demo
func debug_advance_minutes(m: float) -> void
func set_time_scale(x: float) -> void
```
`instance_id` e `plot_id` são inteiros estáveis (salvos). `col` é sempre a coluna inicial do bloco (da esquerda). Itens com `cols = 0` (balde, lata, painel, segunda_caneca) não ocupam colunas (`col = -1` ao comprar).

**Detalhes e extensões do SIM (implementados; valem como contrato):**
- `Sim.new_game(seed := 1, start_tod_hours := -1)` (`< 0` usa `start.fallback_tod_hours`, 9 h). O `Game.new_game()` passa a hora local real se estiver entre 6 h e 21 h; fora disso a Sim abre às 9 h (primeira colheita e primeira visita acontecem com ele acordado). `Game.sim` expõe a Sim; a Sim existe desde o `_init` do autoload.
- `can_buy(...)`, `catalog()[i]` e `antenna_info()` devolvem `missing` (chaves i18n) **mais** `missing_args: Array[Dictionary]` paralelo (`{n:int}` para antenna/rooms/supply/cost/free_cols; `{item:String}` para `missing.item`: a UI traduz `item.<id>.name`). `buy`/`upgrade_antenna` devolvem em `reason` a 1ª chave faltante (ou código: `invalid`).
- `buy(item, room, col)`: com `col < 0` e item que ocupa colunas, usa a 1ª posição de `placement_hints`. `can_place` ignora a instância antiga da linha em itens com `replaces_line`; `placement_hints` põe primeiro as posições sobre ela. Itens com `cols = 0` devolvem `[{room:0,col:-1}]`.
- Escavação: itens `comodo2`/`comodo3` (`line:"escavacao"`) no `catalog()` e em `catalog("escavacao")`; comprar = `dig_room()` (`{ok, reason, room}`); vira job (`active_jobs()` traz `item:"comodo2"`, `instance:-2`); a sala (e `room_dug`) só vale quando o job termina. Uma escavação por vez.
- Obras: o efeito do item (plots, energia, água, caixa) só vale quando o job termina. **Substituição de linha**: a instância antiga some na compra (`item_removed`, sem reembolso), mas `line_tiers()`/oferta/capacidade só sobem quando a nova fica pronta. Não dá para comprar o nível seguinte de uma linha enquanto o anterior está em obra (`missing.item`).
- `demolish` → `{ok, refund, reason}`; recusa (`reason`): `line_item` (itens de linha: só se substituem), `locked` (os 3 vasos iniciais), `house` (itens da casa), `has_overlay` (mesinha com a segunda caneca). Os demais devolvem 100% do pago (`paid`). `move` → `{ok, reason}`; vale para qualquer item com colunas (também em obra).
- Cultura: `set_instance_crop(id, "")` = automático (a melhor cultura liberada para aquela estrutura; **padrão de todas as estruturas**); `crop_order(id)` lê a ordem. A ordem vale na próxima replantada de cada plot. `available_crops` respeita antena e `greenhouse_only`.
- `line_tiers()` → `{plantio: maior tier de plantio pronto (0..3), agua/energia/transporte: id do item pronto}`. `plots()[i].room` acompanha `move`.
- `is_night() == not is_awake()` (acordado 06–22 h). `tod_hours()` é contínuo; o resto avança em passos de `time.step_min`.
- Diário: `diary()` devolve cópias (mais nova primeiro). Entradas: `radio` (falas; `her` quando `speaker == "ela"`), `note` (bilhetes do epílogo), `system` (`journey.arrival`, ao disparar a chegada), `away`. Na volta de uma ausência ≥ `time.away_summary_min_min` (30): uma entrada `away` por fala perdida (`diary.away.line` ou `.night` se de madrugada; args `{hour, speaker}`, a fala em si continua no diário com `while_away:true`), `diary.away.slept` (se dormiu) e o resumo com sufixo de plural (`diary.away.summary[.v1|.n1|.n0|.v1n1|.v1n0]`, args `{hours, visits, scrap, nights}`).
- Rádio: `arrival` na hora; `reaction` `balance.journey.reaction_delay_min` (20) depois; `program/ambient` na hora do dia da chegada + `day_offset`; se a hora de "hoje" já passou, entrega atrasada logo após a reação (sem pular nem duplicar). `radio_line.kind` pode ser também `item` (fala `on_item`, ao comprar item da casa) e `travel`.
- Jornada: `journey().days_left` = dias (float) até o prazo (-1 antes do contato). Extras: `arrival_pending()` (cena do final pendente: o `Game` reemite `arrival_started` após `game_loaded`), `arrival_line()` (`{text_key, cue}` de `journey.arrival`). A chegada só dispara com os 6 itens comprados **e prontos** (a `segunda_caneca` exige a `mesinha`). Epílogo: bilhetes em ordem e em ciclo, `epilogue_notes_per_day` por dia (06–22 h).
- Offline: `Sim.catch_up(elapsed_min, cap_hours := offline_cap)` (mesmo `advance`, **sem** sinais finos: nada de `radio_line`, `item_finished`, `plot_harvested`... só diário) devolve `{hours, visits, scrap, harvested, nights, lines, capped, shown}`. Acima do teto, o relógio salta o excedente (mod 24 h) para manter a hora do dia alinhada. `Game.load_game()` emite `game_loaded` e depois `welcome_back`; um salto do relógio de parede > 120 s (suspensão/hibernação) também cai no catch-up e emite `welcome_back` — **a cena deve reler `instances()`/`plots()` ao receber `welcome_back`**. Relógio que anda para trás é ignorado.
- Save: `Save.write/read/exists/delete` (JSON com `format` e `saved_unix`; escreve `.tmp`, move o antigo para `.bak`, renomeia; a leitura cai no `.bak` se o principal estiver corrompido). `Game.save_summary()` → `{day (1 = primeiro dia), antenna}` ou `{}`. `Game.save_path` é configurável (testes).
- Ritmo (`data/balance.json`, ajustado pelo teste `tests/sim_pace.gd`): `rooms.dig_cost` 40/150, `antenna.cost` 50/100/190/400, prateleira 90, estufa 230, bateria 105, painel 270, cisterna 130, roldana 100; chaves novas: `time.away_summary_min_min`, `economy.meal_hours`, `start.fallback_tod_hours`, `journey.reaction_delay_min`. Antena 5 no dia ~14,8 (bot "equilibrada", 3 check-ins/dia).
- **Ajuda por clique (começo do jogo)**: `help_instance(id)` → `{ok, plots}` / `{ok:false, reason: off|none|cap}` (`help.click_min` min de ciclo por clique, teto `help.day_cap_min` por dia; só vale em estruturas de plantio enquanto a linha de água é a `lata`); `help_box()` → `{ok, scrap}` / `{ok:false, reason: off|empty|cooldown}` (vende na hora, espera `help.box_cooldown_min`; só enquanto o transporte é o `balde`). `help_available()`, `help_plots_available()`, `help_box_available()`. Sinal `helped(instance_id)`. `help_box_check()` → `"ok"|"off"|"empty"|"cooldown"` (confere sem vender). **Cliques são ordens (cena)**: `BunkerView.give_order("instance"|"box", id)` devolve `""` se aceitou ou o motivo (`asleep|full|off|none|empty|cooldown`); a fila `orders` (máx. 4, marcas numeradas no `PlotTip`) é cumprida por `BunkerMan` (modo `order`: anda até o alvo, anima martelar/regar/entregar) e só no fim do passo a cena chama `help_instance`/`help_box` (`finish_order`, sinal `order_done(kind, result)`). À noite as ordens são descartadas. **Andares**: `BunkerMan.walk_to(x, carry, fy)` leva a linha dos pés do destino; se for outro andar ele vai até a escada (x = coluna 0), sobe/desce (passo `climb`) e só então anda. Colheita vai para a despensa (`PANTRY_X`, andar B); o pedido da caixa desce à despensa, pega os cestos, sobe e entrega na escotilha; a escavação é feita no andar da sala nova. `start.sucata` = 6 (o 4º vaso é a primeira compra).
- `plots()[i].eta_min` = minutos de relógio até colher (considera a carga de trabalho e as noites de sono).
- **Guia** (`scripts/ui/hud/`): `Guide.next_goal(game)` lê `balance.guide.order` (`"item"`, `"item:N"` = até ter N, `"antena@N"`) e devolve `{id, antenna, name_key, cost, have, ready, verdict}`; o objetivo fixado vem antes. `StatusHud` (faixa de cima de uma linha: retrato do Joaquim [sinal `man_clicked`], sucata, meta, "faltam N", linha do tutorial), `FirstSteps` (4 passos: ajudar, colher, vender, comprar; estado em `Settings.tutorial`; a cena lê o passo em `BunkerView.tutorial_key`), `IntroScreen` (4 páginas, `Settings.intro_seen`), `InfoCard` (cartões ao clicar: `open_for("man"|"box"|"gen"|"antenna", alvo, janela, id)`, sinal `action("sell"|"gens"|"antenna")`), `ClockText.of(min)` ("1h48"/"45min"/"agora"). `PlotTip` (view): hover com contorno + etiqueta (`hover_lines()`, `hover_grey()`), relógio único, check de planta pronta, selo de caixa cheia, seta do tutorial e "+1 cesto" a cada colheita. `BunkerView`: sinais `man_clicked`, `antenna_clicked`, `generator_clicked(id)`; `rect_of(hit)`, `is_generator(item)`. Game: `box_sale()` → `{units, scrap}`, `help_box_wait()` → `{left, total}` (min de jogo; `help.box_cooldown_min` = 10).
- Testes: `tests/sim_api.gd`, `sim_pace.gd`, `sim_story.gd`, `sim_fuzz.gd`, `sim_game.gd` (+ `sim_bot.gd`, `sim_reach.gd`, `sim_util.gd`, auxiliares). Rodar `godot --headless --path . --import` antes (cache de `class_name`).

### 4.4 `WindowService` (scripts/platform/window_service.gd) [PLATAFORMA]
Controla a janela nativa (ver análise seção 5). Sem efeito (mas sem erro) em `--headless`.
```gdscript
signal layout_changed(logical_size: Vector2i, scale: int)
signal hidden_changed(is_hidden: bool)
signal focus_changed(has_focus: bool)
var logical_size: Vector2i
var ui_scale: int
func set_logical_size(size: Vector2i) -> void   # mantém a borda inferior e a esquerda; ajusta content_scale_size
func set_drawer(open: bool, drawer_h: int = 120, min_width: int = 344) -> void   # cresce para cima; guarda largura
func start_drag() -> void                        # chamado no clique da alça; arrasta até soltar o botão
func is_dragging() -> bool
func set_always_on_top(on: bool) -> void
func set_collapsed(on: bool) -> void             # "esconder": vira uma aba pequena na borda; sim continua
func is_collapsed() -> bool
func reset_position() -> void                    # rodapé da área útil do monitor principal
func set_ui_scale(mode: Variant) -> void         # "auto"|1|2|3|4
func note_activity() -> void                     # qualquer input chama; sobe o FPS temporariamente
func quit_game() -> void                         # salva e sai
```
- Janela **opaca**, sem borda, `ALWAYS_ON_TOP` opcional, `NO_FOCUS` **não** (queremos cliques normais).
- Posição inicial: rodapé da `screen_get_usable_rect` do monitor principal, canto esquerdo; **validar** que o retângulo salvo cruza algum monitor, senão resetar; guardar posição por monitor; tratar mudança de escala (DPI) entre monitores. Escala "auto" = `clamp(floor(altura_monitor/540), 1, 4)`.
- Governador de FPS (`Engine.max_fps`): ativo/hover 30; ocioso (sem input 10 s) 12; sem foco e sem hover 8; recolhido ou `energy_mode=low` 2. Sempre `max_fps` explícito; vsync desligado.
- Ícone de bandeja (`StatusIndicator`, só Windows/macOS): menu Mostrar/Recolher, Resetar posição, Sempre por cima, Sair.
- `--reset-window` na linha de comando reseta a posição.
- **Extras/desvios (módulo plataforma):** `set_logical_size()` recebe o tamanho da FAIXA fechada; `logical_size` é o efetivo (faixa + gaveta, ou 48×16 recolhido). `set_drawer(open, h, min_w)` soma `h` à altura e usa `max(largura_faixa, min_w)`; `is_drawer_open()`. Sinal extra `first_interaction()` (1º clique/tecla; também marca `sound_unlocked` e chama `AudioManager.unlock()` se existir). `note_activity()` já é chamado sozinho em todo input. Recolhido mostra sozinho uma aba desenhada por código (CanvasLayer 100, clique restaura, arrastar move): a cena só precisa reagir a `hidden_changed`. FPS: hover vence recolhido/`low` (12) e arrastar usa 60. Arrasto é manual por padrão (`use_native_drag = false`). Posição salva em `window_pos["WxH@X,Y"] = {x, y}` (distância da esquerda e do rodapé da área útil) + `"_last"`. Acesso à Settings é por nó (`/root/Settings`), I18n/Game/AudioManager também (sem dependência de compilação).
- **Recolher (pedido do dono):** um botão fixo (`icon_hide`) na alça da janela chama `set_collapsed(true)`: a janela encolhe para uma aba pequena (≈48×16 lógicos) colada na borda inferior do canto onde estava, e a simulação continua. Um clique na aba (`icon_show`) restaura o tamanho e a posição anteriores. A aba pode pulsar o sinal de atenção (seção 10) com no máximo uma luz verde. O estado recolhido é salvo em Settings.

### 4.5 `AudioManager` (scripts/audio/audio_manager.gd) [ÁUDIO]
Conecta-se sozinho aos sinais de `Game` no `_ready()` (`item_finished`, `item_placed`, `visit_happened`, `radio_line`, `antenna_changed`, `arrival_started`, `plot_harvested`, `room_dug`, `welcome_back`); não exige chamadas da cena, exceto sfx de interface.
```gdscript
func set_mode(mode: String) -> void             # "silent"|"ambient"|"full" (também lido de Settings)
func set_master_volume(v: float) -> void        # 0..1
func play_sfx(name: String, volume_db: float = 0.0) -> void    # nomes da seção 8
func play_radio_cue(cue: String) -> void        # "static","tone","music_far","music_18h","numbers","voice_her","none"
func set_station(on: bool) -> void              # estação do bunker (modo ambiente/estudo: faixas contínuas com chiado)
func station_next() -> void
func is_station_on() -> bool
func refresh_machine_loops() -> void            # lê Game.instances() e liga um loop por máquina
func unlock() -> void                           # primeira interação: libera o som (padrão silencioso até lá)
```
Barramentos: `Master`, `Radio` (filtro passa-banda + chiado), `Ambient`, `UI`. Modo *silent*: nada toca; *ambient*: ambiente e SFX baixos, **rádio só em texto**; *full*: tudo. Padrão `ambient`, mas **silencioso até `unlock()`**. Nada toca em `--headless`.
Notas da implementação (módulo de áudio): `unlock()` também é chamado sozinho na primeira entrada de mouse/teclado e grava `Settings.sound_unlocked`. Barramentos: SFX de interface (`click, hover, buy, error, page, switch`) vão para `UI`; `radio_on, tune, blip` e a estação/cues para `Radio` (**bloqueados no modo ambient**, exceto a estação ligada pelo jogador); o resto do mundo e os loops, `Ambient`. `play_radio_cue` aceita também `"epilogue"` (tema da chegada; `arrival_started` toca `hatch_open` e, em *full*, o epílogo). Extras para teste: `bind_game(node)`, `bind_settings(node)`, `record_plan`/`plan`, `compute_loops()`, `loop_plan()`. Itens -> loop: `bicicleta→bike, moinho→windmill, bateria→battery, bomba→pump, esteira/roldana→conveyor, estufa→greenhouse, painel→solar, gotejador/cisterna→drip` (só `state=="ready"`).

---

## 5. Dados de conteúdo

### 5.1 `data/radio.json`
```json
{ "lines": [
  { "id": "l2_arrival", "level": 2, "kind": "arrival", "speaker": "sementes",
    "day_offset": 0, "hour": null, "text_key": "radio.l2_arrival", "cue": "static" }
] }
```
- `kind`: `arrival` (entregue na hora em que a antena chega a `level`; no nível 1, no início do jogo), `program` (entregue na hora de relógio `hour` (0–24 float) do dia `arrival_day + day_offset`), `reaction` (do homem, 20 min depois da `arrival` do mesmo nível; `speaker: "ele"`), `ambient` (nível 1: chiado e restos, programadas como `program`).
- `speaker`: `ruido`, `sementes`, `caravana`, `numeros`, `velho`, `norte`, `ela`, `ele`. `cue`: `static|tone|music_far|music_18h|numbers|voice_her|none`.
- Cada linha tem 1 a 3 frases curtas (cabem em um balão de ~140 caracteres) e as chaves `radio.<id>` em `strings_story.csv`.
- Conteúdo: ~30 linhas, níveis 1–5. A voz dela (`l5_arrival`, speaker `ela`, cue `voice_her`): *"Eu tô viva. Tô a caminho. Vai demorar, mas eu vou chegar."* (ou variação fiel a isso).

### 5.2 `data/journey.json` (pós-contato)
```json
{ "on_item": { "cama_dela": {"text_key":"journey.on_cama_dela","cue":"static"} },
  "travel": [ {"id":"t1","day_offset":1,"hour":12.5,"text_key":"journey.t1","cue":"static"} ],
  "arrival": { "text_key": "journey.arrival", "cue": "none" },
  "epilogue_notes": ["note.1","note.2"] }
```
- Ao comprar um item da casa, sai a fala `on_item` dela. As `travel` (≈10) saem em ordem por dia após o contato (progresso de viagem: "passei pelo rio", "faltam dois dias"). **Chegada**: quando todos os `house_items` estão comprados **e** passaram `arrival_min_days_after_contact` dias desde o contato (`balance.journey`), `Game` emite `arrival_started`, e ao final da cena (a cena chama `Game.finish_arrival()`) vira modo epílogo: `arrived() == true`; passam a sair `epilogue_notes` (bilhetes na mesa, `kind:"note"`) `epilogue_notes_per_day` por dia.
- `Game.finish_arrival()` também existe (a cena chama ao terminar).

### 5.3 Diário
Lista cronológica (mais nova no topo) de falas, bilhetes e entradas `away` (resumo de ausência, gerado: chave `diary.away.summary` com `{hours}`, `{visits}`, `{scrap}`, `{nights}`; e `diary.away.line` para cada fala perdida). Entradas têm `read`.

---

## 6. Internacionalização (chaves)

CSV `key,pt_BR,en`. Um arquivo por módulo:
- `strings_story.csv` [CONTEÚDO]: `radio.*`, `speaker.*`, `journey.*`, `note.*`, `ending.*`, `diary.*` (inclui `diary.away.*`).
- `strings_items.csv` [CONTEÚDO]: `item.<id>.name`, `item.<id>.desc` (1 frase: "pra quê?"), `crop.<id>.name`, `line.<id>`, `pra_que.<renda|tempo|espaco|porta|historia>`, `missing.*` (frases curtas de requisito: `missing.antenna` "Antena nível {n}", `missing.rooms`, `missing.supply`, `missing.cost`, `missing.free_cols`, `missing.item`, `missing.max`), `antenna.<n>.name`.
- `strings_ui.csv` [UI]: `ui.*`, `title.*`, `opt.*`, `hint.*`, `tab.*`, `toast.*`.
Placeholders `{nome}`. Nenhuma frase longa: a faixa é minúscula.
- Chaves extras de `strings_items.csv`: `item.<id>.name|desc` (desc ≤ 60 caracteres), `item.comodo2|comodo3.name|desc` e `room.dig2|dig3[.desc]` (escavação), `room.name`, `pra_que.<x>.help`, `fixed.<id>[.desc]`, `behavior.<id>` (gerúndio: "Lendo"). `pra_que.porta` = pré-requisito que libera a próxima melhoria.
- `strings_ui.csv` (base para o módulo UI): botões são `*.btn` / `*.btn.*` (≤ 14 caracteres); abas `tab.build|radio|state|options` (4 no máximo); `title.*`, `opt.*` (`opt.scale.auto|1|2|3|4`, `opt.text_size.normal|large|huge` ≙ 1.0/1.25/1.5), `hint.*`, `toast.*`, `welcome.*` (placeholders `{hours} {visits} {scrap} {harvested} {nights} {n}`), `goal.*`, `crop.*`, `buy.*`, `status.*`, `tray.*`, `ending.credits`.

---

## 7. Arte (pixel art gerada por código, paleta fixa)

Ferramentas: `tools/art/palette.py` (**28 cores; tudo passa por `snap_image`**; `check_image` para validar). Cada gerador é um script Python (`python3 tools/art/make_*.py`) reproduzível e idempotente que escreve PNGs em `assets/art/` e um `manifest_<grupo>.json`. Fundo transparente, alfa binário, **sem suavização**. Cor `signal` só em sinais. Luz sempre vindo da lâmpada do teto (realce amber no topo/lado esquerdo dos objetos, sombra dark no baixo/direito), contorno `ink`/`dark1` de 1 px só onde ajuda a silhueta. Tudo com cara de **sucata/gambiarra** (fita, arame, lata, garrafa PET, cano). Tom grounded, nada fantasioso.

Manifest (um por grupo; o carregador junta todos os `assets/art/manifest_*.json`):
```json
{ "vaso": { "file": "env/vaso.png", "frame_w": 16, "frame_h": 16, "frames": 1, "fps": 0,
            "anchor": [8, 16], "plots": [[8, 14]] } }
```
- PNG = tira horizontal de `frames` quadros `frame_w×frame_h`. `anchor` = ponto de ancoragem em px dentro do quadro (para objetos: embaixo no centro; personagem: pés).
- `plots` (só estruturas de plantio): posições (x,y) **relativas ao canto superior esquerdo do sprite** onde fica a base-centro de cada planta (sprite de planta 12×12).
- Variantes: `earth_0`, `earth_1`, …

### 7.1 Ambiente + objetos + UI → três geradores, três pastas, três manifestos
Para não haver conflito de arquivos, a tabela abaixo foi dividida: **[ARTE-AMBIENTE]** faz `assets/art/env/` + `manifest_env.json` (terra, grama, parede, chão, teto, divisória, escada, escotilha, hatch_box, scrap_pile, antenas, radio_table, radio_glow, bed, lamp, fx_*, bubble_thought); **[ARTE-OBJETOS]** faz `assets/art/obj/` + `manifest_obj.json` (vaso…esteira, crop_*, estante…foto_dela, caneca); **[ARTE-UI]** faz `assets/art/ui/` + `manifest_ui.json` (panel_9s, button_9s_*, icon_*). O campo `file` do manifesto inclui a subpasta (`env/vaso.png` → `obj/vaso.png`). O carregador junta todos os `manifest_*.json`.
| Nome | Quadro | Fr. | Notas |
|---|---|---|---|
| earth_0..3 | 16×16 | 1 | terra maciça (variações leves, sem repetição óbvia) |
| earth_deco_0..2 | 16×16 | 1 | pedra, raízes, lata enterrada |
| grass_0..2 | 16×8 | 1 | topo da superfície |
| wall_0..3 | 16×16 | 1 | parede do fundo da sala (concreto manchado, umidade) |
| floor_0..1 | 16×8 | 1 | chão (concreto/tábuas) |
| ceiling_0..1 | 16×8 | 1 | teto com canos e cabo |
| divider | 8×56 | 1 | divisória com vão de porta 8×32 (y 16..48 do sprite), chão sólido embaixo |
| ladder | 16×16 | 1 | tile vertical da escada |
| hatch | 32×16 | 2 | tampa da escotilha (fechada, aberta) sobre a grama |
| hatch_box | 16×16 | 4 | caixa de trocas: vazia, 1/3, 2/3, transbordando |
| scrap_pile | 16×16 | 3 | sucata deixada (pequena, média, grande) |
| antenna_1..5 | 24×24 | 1 | mastro de varal e cabo de vassoura (1) até antena elaborada (5); base embaixo no centro |
| radio_table | 16×16 | 3 | mesa+rádio: desligado, chiado A, chiado B |
| radio_glow | 16×16 | 2 | **overlay** de sinal (verde-mostrador piscando) |
| bed | 32×16 | 1 | cama de campanha |
| lamp | 16×8 | 3 | lâmpada do teto: apagada, acesa, piscando |
| vaso | 16×16 | 1 | plots: [[8,14]] |
| canteiro | 32×16 | 1 | plots: 3 |
| prateleira | 32×32 | 1 | plots: 5 (dois andares) |
| estufa | 48×32 | 1 | garrafas PET; plots: 6 |
| crop_batata / crop_feijao / crop_tomate | 12×12 | 4 | estágios 0 semente, 1 broto, 2 folhas, 3 madura; âncora base-centro |
| gotejador | 16×16 | 2 | parado, pingando (fps 2) |
| cisterna | 32×32 | 2 | tanque (fps 1) |
| bomba | 16×16 | 3 | bomba (fps 6) |
| bicicleta | 16×16 | 4 | gerador de bicicleta (4 pedaladas, fps 8) |
| moinho | 16×32 | 4 | moinho no duto de ar (hélice, fps 8) |
| bateria | 32×16 | 2 | bateria de carro + LED |
| painel | 32×16 | 1 | painel solar (na superfície) |
| calha | 16×16 | 3 | calha com cestos escorregando (fps 4) |
| roldana | 16×32 | 4 | roldana com corda (fps 6) |
| esteira | 32×16 | 4 | esteira (fps 8) |
| estante | 16×32 | 1 | estante de caixotes com livros |
| poltrona | 16×16 | 1 | poltrona de sucata |
| mesinha | 16×16 | 1 | mesa com papel e lápis |
| foto | 16×16 | 1 | quadro na parede (paisagem desbotada; **sem rosto**) |
| cama_dela | 32×16 | 1 | cama arrumada ao lado |
| cantinho | 32×16 | 1 | tapete + abajur |
| planta_dela | 16×16 | 1 | planta em vaso de lata |
| cabide | 16×32 | 1 | cabide com um casaco |
| caneca | 8×8 | 2 | 1 caneca; 2 canecas (overlay na mesinha) |
| foto_dela | 16×16 | 1 | quadro na parede (**sem rosto**) |
| fx_zzz, fx_drip, fx_spark, fx_dust, fx_steam, fx_scrap_pop | 8×8 (drip 4×8) | 4 | partículas pequenas |
| bubble_thought | 24×20 | 1 | balão de pensamento com rabinho |
| panel_9s | 16×16 | 1 | moldura do painel (margens 5) |
| button_9s_normal/hover/pressed/disabled | 12×12 | 1 | 9-slice (margens 4) |
| bar_back_9s / bar_fill_9s | 8×6 | 1 | barra de progresso, margens 3. Ocupam o **mesmo retângulo**: desenhe a calha inteira e a faixa de enchimento por cima, com a largura proporcional (ambas com contorno ink) |
| tab_normal / tab_active | 12×10 | 1 | abas 9-slice, margens 3; a ativa não tem borda de baixo (cola no painel, mesmo tom do miolo) |
| (manifest_ui) | | | cada entrada 9-slice traz `"margins": [esq, topo, dir, base]` (usar em `StyleBoxTexture.texture_margin_*`); ícones têm `anchor [4,4]`. Fonte: `assets/fonts/Jersey15-Regular.ttf` (ver `assets/fonts/ui_theme_hint.md`: 13 normal, 12 pequeno, 15 título) |
| icon_* | 8×8 | 1 | `sucata, cesto, energia, radio, antena, espaco, tempo, porta, historia, renda, estrela, check, lock, arrow_up, arrow_down, close, speaker_on, speaker_off, hide, show, gear, book, hammer, home, plus, crop_batata, crop_feijao, crop_tomate, grab` (ícones legíveis em 8 px; `estrela` e `check` usam a cor signal) |

Notas [ARTE-OBJETOS]: os `crop_*` têm `anchor [6,12]` (base-centro; o pé cai em `plots`); a prateleira usa plots `[[6,28],[16,28],[26,28],[11,14],[21,14]]` (andar de baixo, depois o de cima) e a estufa `[[8,19],[21,19],[34,19],[14,29],[27,29],[40,29]]` (fileira de trás, depois a da frente); as estruturas não têm pixels opacos acima da linha de terra, então a planta pode ser desenhada por cima ou por baixo. A `caneca` tem `overlay_on:"mesinha"` e `overlay_pos:[8,0]` (canto sup. esq. do overlay dentro da mesinha). `bateria` pisca a 2 fps. A folha `_contact_obj*.png` não entra no manifesto.

Plots por estrutura (x,y do pé de cada planta no sprite): vaso `[[8,14]]`; canteiro `[[6,14],[16,14],[26,14]]`; prateleira 5 posições em 2 andares; estufa 6 em 2 fileiras.

### 7.2 Personagem [ARTE-PERSONAGEM] → `assets/art/man/`, `manifest_man.json`
Todos 32×32 por quadro, de lado olhando para a **direita** (a cena espelha), âncora nos pés `[16, 31]`. Um homem de ~40 anos, barba por fazer, cabelo curto escuro, camisa de trabalho `cloth1/cloth2`, calça `dark2`, botas `ink`, pele `skin1/skin2`. Silhueta clara: cabeça ~10 px, braços e ferramenta destacados do corpo. **Poucas poses base** e adereços desenhados junto.
| Nome | Fr. | fps | Uso |
|---|---|---|---|
| man_idle | 4 | 3 | em pé respirando |
| man_walk | 6 | 8 | andando |
| man_carry | 6 | 8 | andando com um cesto nos braços |
| man_crouch | 4 | 4 | agachado plantando/colhendo |
| man_water | 4 | 5 | regando com a lata |
| man_hammer | 4 | 6 | martelando (obra) |
| man_dig | 4 | 6 | cavando com pá (escavar sala) |
| man_pedal | 4 | 8 | pedalando (sentado sobre a bicicleta; só o corpo) |
| man_sleep | 2 | 1 | deitado dormindo (sobre a cama) |
| man_sit_read | 4 | 2 | sentado lendo (na poltrona; só o corpo) |
| man_sit_listen | 4 | 2 | sentado escutando o rádio, cabeça inclinada |
| man_nap | 2 | 1 | sentado cochilando, cabeça baixa |
| man_write | 4 | 4 | em pé escrevendo na mesinha |
| man_photo | 2 | 1 | em pé olhando uma foto |
| man_eat | 4 | 4 | em pé comendo de uma lata |
| man_look_up | 2 | 1 | olhando para cima (chegada dela) |

### 7.3 Verificação de arte
Cada gerador termina rodando `check_image` em todos os PNGs e imprime `OK` ou a lista de problemas. O agente **tem que abrir os PNGs (ampliados ×6 numa folha de contato) e olhar**: a silhueta de cada coisa tem que ser reconhecível em 16 px; descreva no relatório o que ficou fraco.

---

## 8. Áudio (sintetizado por código) [ÁUDIO]

Geradores Python em `tools/audio/` (numpy; `pip install` permitido para o que faltar) → WAV mono 22,05 kHz → `ffmpeg` converte para **OGG** em `assets/audio/<grupo>/<nome>.ogg` (loops com `loop` ligado no `.import` ou tratados pelo manager). Tudo com cara de rádio velho/ambiente de concreto, **baixo volume, sem agudos duros**.
- `sfx/`: `click, hover, buy, hammer_1, hammer_2, hammer_3, dig, knock, scrap, harvest, pour, radio_on, tune, blip, error, step_1, step_2, hatch_open, page, place, switch`
- `loops/` (20–30 s, sem emenda audível): `amb_room, bike, windmill, battery, pump, conveyor, greenhouse, solar, drip, wind_surface, static`
- `music/` (pelo rádio; abafadas): `far` (valsa distante, 45–60 s, nível 2), `18h` (melodia calorosa do velho, 60 s, nível 4), `numbers` (estação de números: bipes e tons), `station_1, station_2, station_3` (ambiente/estudo, ~90 s cada, calmas), `epilogue` (tema curto da chegada), `her_voice` (**placeholder**: motivo de dois tons com chiado abrindo; a voz real será gravada depois)
`assets/audio/bus_layout.tres` (barramentos Master, Radio, Ambient, UI; filtro no Radio) também é do módulo de áudio.
Acréscimo: `loops/amb_night` (loop de noite, usado quando `Game.is_night()`). `music/her_voice` é **PLACEHOLDER** (motivo de dois tons com chiado abrindo, ~8 s): a voz real será gravada depois e substitui o arquivo com o mesmo nome. Geradores: `python3 tools/audio/make_all.py` (gera tudo e imprime tabela) e `python3 tools/audio/analyze.py` (pico, LUFS, clipping, espectro, emenda dos loops). O `bus_layout.tres` é gerado por `tools/audio/make_bus_layout.gd`. Os arquivos têm todos pico -6 dBFS (SFX) ou ~-14 LUFS (máquinas/músicas) ou mais baixo (ambientes); o nível relativo é aplicado pelo `AudioManager` (tabelas `SFX_GAIN_DB`, `LOOP_DB`).

---

## 9. Comportamentos do homem (para a cena)

Máquina de estados na cena (visual **representativo**: a produção vem do `Sim`):
1. **Noite** (`is_night()` ou não acordado): dorme na cama (`man_sleep`).
2. **Obra** (`active_jobs()` não vazio): vai até o local e martela (`man_hammer`; `man_dig` se for escavação).
3. **Trabalho** (a cada decisão, com probabilidade ≈ `busy()`): escolhe um plot pronto (progress ≥ 0.95) → `man_crouch` e colhe → `man_carry` até `hatch_box` → solta; ou rega (`man_water`) um plot sem irrigação automática; ou pedala se a energia for bicicleta (`man_pedal` sobre a `bicicleta`).
4. **Livre** (resto do tempo): sorteia entre atividades **desbloqueadas pelos objetos** (`unlocked_behaviors()`): `ler` (estante → sentado na poltrona ou em pé), `cochilar`, `ouvir_radio` (poltrona/perto do rádio), `escrever` (mesinha), `olhar_foto` (foto); sempre pode `man_idle`, andar um pouco, comer ao meio-dia (`man_eat`).
5. Faminto: velocidade de caminhada × 0,6 e balão de pensamento com `icon_cesto`.
6. Chegada dela: ver `Game.arrival_started` (cena do final: a escotilha abre, a luz desce pelo poço, ele olha para cima com `man_look_up`; corte; depois `arrival_finished`).
Não há sprites dela. No epílogo a `caneca` mostra o quadro 2 (duas canecas) e o casaco do `cabide` aparece.

---

## 10. Sinais de atenção (sem nag)
Luz verde pulsando no rádio (`radio_glow`) quando há fala nova não lida; caixa transbordando quando `box_fill()>1`; lâmpada piscando quando `!power_ok()`; balão de pensamento com o ícone do objetivo fixado quando `goal_ready()`. Regras: nada de som, nada de pop-up, no máximo **um** elemento pulsando por vez; pulsa 10 s e para quando o jogador passa o mouse; só volta com evento novo.

---

## 11. Testes mínimos esperados
- `tests/sim_*.gd`: simulação de N dias com um bot que compra pela ordem do plano; assert: antena 5 entre `test_targets.antenna5_day_min/max`; offline == online (mesmo resultado dentro de tolerância); salvar/carregar sem perda; nenhuma compra deixa o jogo sem saída (dependências alcançáveis).
- `tests/shot_*.gd`: capturas de tela da cena em estados fixos (para olhar).
