# Telas (módulo ui-telas)

Tudo é montado por código; as cenas em `scenes/ui/` só têm o nó raiz com o script.
Todas leem os autoloads por nome (`ScreenUtil.call_on`), então funcionam com stubs.
Refazem os textos sozinhas em `I18n.locale_changed` e em `Settings.changed("text_size")`.

| Cena | Classe | API |
|---|---|---|
| `scenes/ui/title.tscn` | `TitleScreen` | sinais `game_started(is_new)`, `options_requested()`, `quit_requested()`; `focus_first()`; `use_live_bunker` (instancia `scenes/bunker/bunker.tscn` ao fundo se existir; senão usa a arte estática). Chama `Game.load_game()` / `Game.new_game()` (confirma se `has_save()`), `AudioManager.unlock()`, `WindowService.quit_game()`. Mostra "Dia · Antena" se `Game.save_summary() -> {day, antenna}` existir. Tamanho: `TitleScreen.SIZE` (344×208), quem integra ajusta a janela. |
| `scenes/ui/options.tscn` | `OptionsScreen` | sinais `closed()`, `progress_erased()`; `show_header` (false dentro da aba da gaveta). Grava em Settings e aplica na hora: `I18n.set_locale`, `AudioManager.set_mode/set_master_volume`, `WindowService.set_ui_scale/set_always_on_top/reset_position`, `Game.delete_save()` (com confirmação). Bandeja só no Windows/macOS. |
| `scenes/ui/handle.tscn` | `WindowHandle` | 48×12, canto superior direito: arrastar (`start_drag`), gaveta, som, recolher. Sinais `drawer_toggled(open)`, `collapsed_changed(on)`; `set_drawer_open(open)`, `set_collapsed(on)`, `notify_attention()`. Recolhida desenha a aba 48×16 (icon_show, rádio, 1 luz verde) na camada 101, por cima da aba genérica do WindowService; a luz acende com fala não lida, objetivo pronto, caixa transbordando ou falta de energia, pisca 10 s (para no hover; fixa com "reduzir piscadas"). |
| `scenes/ui/ending.tscn` | `EndingScreen` | `play_arrival()`, `show_next_day()`, `show_demo_end()`, `skip_to_end()`; sinal `finished(kind)` com `arrival`, `next_day`, `demo_continue`, `demo_quit`. Não chama `Game.finish_arrival()`. |
| (sem cena) | `HintLayer` | `HintLayer.new()` por cima da faixa. Uma dica por vez, some sozinha, nunca repete (`Settings.hints_seen`). Automáticas: novo jogo (first_run, drag, hide), welcome_back (offline), 1ª fala (radio), caixa cheia (box), sem energia (power). Outras: `HintLayer.request("build")`. `enabled = false` segura a fila (ex.: com o título aberto). |
| (sem cena) | `ConfirmBox` | `ConfirmBox.ask(parent, title_key, text_key, ok_key, on_ok)`; Cancelar é o foco padrão. |

Testes: `tests/ui_screens_theme.gd`, `tests/ui_screens_flow.gd` (dublês em `tests/ui_screens_fakes.gd`),
capturas `tests/ui_screens_shot.gd` (xvfb + opengl3, `OUT_DIR=<pasta>`).
