# Gaveta (módulo ui-gaveta)

Montada por código; `scenes/ui/drawer.tscn` só tem o nó raiz (`Control` em tela cheia) com `drawer.gd`.
Lê `Game`, `I18n`, `WindowService`, `AudioManager` e `Settings` por nó (`/root/...`), então compila em
`--check-only` e funciona com stubs. Tema: `UiTheme.build()` (refeito em `Settings.changed("text_size")`).

## Onde fica

- Instancie `scenes/ui/drawer.tscn` num `CanvasLayer` acima do bunker. A raiz não pega cliques (`MOUSE_FILTER_IGNORE`).
- Aberta: a gaveta ocupa y `0..Drawer.DRAWER_H` (120) e chama `WindowService.set_drawer(true, 120, 344)`.
  **A faixa do bunker tem que estar em y = 120** enquanto ela está aberta (a camada de posicionar fica em
  y 120..208 e usa a geometria da seção 3 do contrato, salas a partir de 1: `x = 8 + (sala-1)*200 + col*16`, y 40..80).
- Fechada: só os avisos (toasts) aparecem, no céu da faixa, canto direito.

## API (`class_name Drawer`)

| | |
|---|---|
| `open(tab := "")`, `close()`, `toggle(tab := "")`, `is_open()` | abas: `"build"`, `"radio"`, `"state"` (+ a 4ª) |
| `show_tab(id)`, `current_tab()` | sair da aba Rádio marca o diário como lido |
| `select_instance(instance_id)` | abre Construir com o objeto (cultura, mover, desmontar). A cena do bunker pode chamar no clique de um objeto; com a gaveta aberta na aba Construir a própria gaveta já deixa clicar nos objetos da faixa |
| `add_tab(id, title_key, icon, page: Control)` | até 4 abas. Opções: `add_tab("options", "tab.options", "gear", options)` com `OptionsScreen.show_header = false` |
| `toast(key, args := {}, icon := "")` | aviso curto; `key` sem tradução é usada como texto pronto |
| `show_welcome(summary)` | já ligado a `Game.welcome_back`; abre a gaveta com o resumo |
| `bind_game(node)` | o padrão é `/root/Game`; os testes passam um falso |
| sinais | `open_changed(is_open)`, `tab_changed(id)`, `placement_changed(mode, item_id)` (mode `""`, `"buy"`, `"move"`) |

`WindowHandle.drawer_toggled(open)` → `drawer.open()`/`close()`; `drawer.open_changed` → `handle.set_drawer_open()`.
Esc fecha (ou cancela o posicionamento); botão direito na faixa cancela.

## Abas

- **Construir**: catálogo por linha (setas trocam a linha; "Tudo" agrupa), antena no topo. Detalhe: "pra quê?",
  requisitos que faltam (`missing` + `missing_args`), comprar (itens com colunas entram no modo de posicionar com
  `placement_hints`; `cols = 0` compra direto; `comodo*` chama `dig_room()`), fixar objetivo (aparece quando ainda
  não dá pra comprar). Objeto escolhido: cultura (Automático + culturas liberadas), mover, desmontar (com confirmação;
  recusas `line_item`/`locked`/`house`/`has_overlay` viram aviso traduzido). A linha "Casa dela" só aparece depois do contato.
- **Rádio**: diário (mais nova no topo, barra verde nas novas), contador, marcar lidas, estação liga/desliga e troca
  (`AudioManager.set_station/station_next/is_station_on`).
- **Estado**: o que ele está fazendo (`status.*`), dia e hora, ocupado %, sucata, caixa (estoque, barra, trocas por dia),
  energia, antena; depois do contato, os 6 itens da casa e quantos dias faltam.

Avisos automáticos: obra começou, ficou pronto, desmontado, mudou de lugar, escavação, antena, item da casa,
objetivo pronto. Sem som. Um por vez, 3 s.

Textos novos em `data/i18n/strings_drawer.csv` (chaves `drawer.*`).

Testes: `tests/ui_drawer_test.gd` (Game falso em `tests/ui_drawer_fake_game.gd`), `tests/ui_drawer_real.gd`
(Sim de verdade), capturas `tests/ui_drawer_shot.gd -- <pasta>` (xvfb + opengl3).
