# Quantos Dias?

Idle cozy numa faixa baixa da tela. Um homem sozinho num bunker depois do fim do mundo planta, junta sucata, monta gambiarras e melhora a antena do rádio, à espera da esposa que ficou lá fora. A janela fica grudada no rodapé da tela (acima da barra de tarefas) enquanto você trabalha, e o jogo anda sozinho, inclusive com ele fechado.

- Motor: Godot 4.6 (GDScript tipado, renderizador Compatibility).
- Plataforma alvo: Windows 10/11 x64. Roda também no Linux pelo editor.
- Idiomas: português (Brasil) e inglês.
- Design: [`docs/analise-de-design.md`](docs/analise-de-design.md). Interfaces entre módulos: [`docs/CONTRATOS.md`](docs/CONTRATOS.md). Roteiro do rádio: [`docs/roteiro.md`](docs/roteiro.md).

## Como jogar (Windows)

1. Baixe `QuantosDias-windows-x64.zip`, extraia e rode `QuantosDias.exe`. Não precisa instalar nada.
2. Na primeira vez o Windows SmartScreen pode avisar que o app não é reconhecido (o exe não é assinado): clique em **Mais informações → Executar assim mesmo**.
3. O progresso e as opções ficam em `%APPDATA%\QuantosDias\` (`settings.json` e o save). Apague a pasta para começar do zero.

## Primeiros minutos

Ao começar um jogo novo há uma introdução de 4 telas (por que o jogo anda sozinho, o que é a sucata, o que fazer). Depois, enquanto o homem ainda não tem máquinas, **você ajuda com cliques**:

1. Clique num vaso: ajuda a planta a crescer (cada clique adianta o ciclo; cinco cliques fecham a primeira colheita).
2. Clique na caixa da escotilha: troca os cestos por sucata na hora (com um tempo de espera).
3. Junte sucata e compre o **Vaso** extra (o próximo objetivo aparece sempre na faixa de cima).

Cada máquina tira um clique do seu trabalho: o **gotejador** rega sozinho (os vasos deixam de aceitar clique) e a **calha** leva os cestos sozinha (a caixa deixa de aceitar clique). A partir daí o homem toca tudo e você só decide o que construir. A faixa de cima mostra sucata, cestos na caixa e o próximo objetivo; clicar nela abre a aba Construir, onde o item sugerido vem marcado com uma estrela. Passe o mouse numa planta para ver cultura, fase, % e quanto falta para a colheita. A aba **Estado** tem a "Mochila" (colhido, vendido, sementes e ferramentas).

## Controles

Tudo é com o mouse.

| Ação | Como |
|---|---|
| Construir, plantar, melhorar a antena | Botão da seta na alça (ou clique na escotilha/caixa): abre a gaveta, aba **Construir**. Escolha o item, depois o lugar na faixa |
| Ouvir o rádio / ler o Diário | Clique na mesa do rádio ou aba **Rádio** da gaveta (a luz verde pulsa quando há fala nova) |
| Ver o estado (sucata, caixa, energia, jornada da casa) | Aba **Estado** |
| Trocar a cultura de um vaso, mover ou desmontar | Clique no objeto na faixa |
| Opções (idioma, áudio, escala, sempre por cima, apagar progresso) | Aba **Opções** ou tela de título |
| Mover a janela | Arraste pela alça (ícone da mão); ela fica dentro da área útil do monitor |
| Recolher | Botão de esconder na alça: a janela vira uma aba pequena na borda de baixo e o jogo continua. Clique na aba para voltar |
| Sempre por cima, resetar posição, sair | Menu do ícone na bandeja do Windows (perto do relógio) |
| Janela sumiu da tela | Menu da bandeja → Resetar posição, ou rode `QuantosDias.exe --reset-window` |

Esc fecha a gaveta ou cancela o posicionamento. Fechar o jogo e voltar depois: o tempo passado conta (até 72 h) e a gaveta mostra um resumo do que aconteceu.

O som começa desligado e só liga depois do primeiro clique. Nas opções há três modos de áudio: silencioso, ambiente e completo.

## Rodar pelo código

```bash
# Godot 4.6: GODOT_BIN=/caminho/do/godot ou `godot` no PATH
bash Ferramentas/godot.sh --path .            # abre o jogo
bash Ferramentas/godot.sh -e --path .         # abre o editor
bash Ferramentas/godot.sh --headless --path . --import   # importa as imagens/áudio depois de gerar
```

No Windows, abra o `project.godot` no Godot 4.6 e aperte F5.

## Testes

```bash
bash tests/run_all.sh          # roda todos os tests/*.gd e mostra o resumo
bash tests/run_all.sh sim_     # só os que têm "sim_" no nome
```

Scripts `extends SceneTree` rodam headless. Testes com cena (`tests/<nome>.tscn`) e capturas (`shot_*`) precisam de tela: no Linux rodam com `xvfb-run` e salvam PNG em `build/tests/`; sem `xvfb-run` são pulados. O script sai com código 1 se algum teste falhar.

Antes de entregar uma mudança em `.gd`: `bash Ferramentas/godot.sh --headless --path . --check-only --script <arquivo.gd>` e `bash Ferramentas/godot.sh --headless --path . --quit-after 60`.

## Exportar para Windows

Precisa dos export templates do Godot 4.6 (no editor: *Editor → Gerenciar modelos de exportação → Baixar*; ou extraia o `Godot_v4.6-stable_export_templates.tpz` em `~/.local/share/godot/export_templates/4.6.stable/` no Linux, `%APPDATA%\Godot\export_templates\4.6.stable\` no Windows).

```bash
bash tools/build/export_windows.sh            # release
bash tools/build/export_windows.sh --debug    # template de debug
```

O script:
1. regenera o ícone a partir da arte (`tools/build/make_icon.py`, precisa do Pillow; sem ele usa o `icon.ico` já versionado);
2. importa os recursos;
3. exporta o preset **Windows Desktop** para `build/windows/QuantosDias.exe` (pck embutido, sem console, ícone e versão no exe);
4. valida: exporta o `.pck`, roda a cena principal headless com `--main-pack` por 120 quadros e falha se aparecer erro;
5. gera `build/QuantosDias-windows-x64.zip`.

Pelo editor também funciona: *Projeto → Exportar → Windows Desktop*. O preset está em `export_presets.cfg` e inclui `*.csv, *.json, *.ogg, *.png` (o Godot não empacota CSV e JSON sozinho). Ficam fora: `tests/`, `docs/`, `tools/`, `Ferramentas/` e as folhas de contato `_*.png` da arte.

Depois do export, siga o roteiro de teste manual em [`docs/TESTE_NO_WINDOWS.md`](docs/TESTE_NO_WINDOWS.md).

## Estrutura

```
project.godot            configuração e autoloads (Settings, I18n, Game, WindowService, AudioManager)
export_presets.cfg       preset de export Windows
scenes/                  main.tscn, cena do bunker, interface
scripts/sim/             simulação, balanceamento, save (Game)
scripts/platform/        Settings e WindowService (janela, gaveta, recolher, bandeja)
scripts/i18n/            I18n e leitor de CSV
scripts/audio/           AudioManager
scripts/view/, ui/       cena do bunker e interface
data/balance.json        todos os números do balanceamento
data/radio.json, journey.json   falas do rádio e pós-contato
data/i18n/strings_*.csv  textos em PT-BR e EN
assets/art/              pixel art gerada por código + manifest_*.json
assets/audio/            áudio sintetizado por código (OGG) + barramentos
assets/fonts/            fonte Jersey 15 e licença
tools/art, tools/audio   geradores Python da arte e do áudio
tools/content            conferência de textos e conteúdo
tools/sim_oracle         simulação da economia em Python (referência do ritmo)
tools/build              ícone e script de export
tests/                   testes headless e run_all.sh
docs/                    design, contratos, roteiro, teste no Windows
```

## Licenças e créditos

- **Jogo, código, design e roteiro:** Vinícius.
- **Fonte:** Jersey 15, de The Soft Type Project (Sarah Cadigan-Fried), sob a SIL Open Font License 1.1. Texto da licença em [`assets/fonts/OFL.txt`](assets/fonts/OFL.txt); detalhes em [`assets/fonts/README_fonte.md`](assets/fonts/README_fonte.md).
- **Arte:** pixel art gerada por código pelos scripts de `tools/art/` com paleta fixa; não usa imagens de terceiros. Faz parte do projeto e segue a mesma licença do jogo.
- **Áudio:** efeitos, loops e músicas sintetizados por código pelos scripts de `tools/audio/` (numpy, convertidos para OGG com ffmpeg); não usa gravações de terceiros. A voz dela é um placeholder sintético até a gravação real.
- **Motor:** [Godot Engine](https://godotengine.org), licença MIT. O exe exportado inclui o Godot e as bibliotecas de terceiros dele; os avisos de licença estão em `Engine.get_license_text()` e em https://godotengine.org/license.
- Feito com a ajuda do Claude (Anthropic).
