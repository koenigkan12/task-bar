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

Ao começar um jogo novo há uma introdução de 4 telas (por que o jogo anda sozinho, o que é a sucata, o que fazer). Depois, enquanto o homem ainda não tem máquinas, **seus cliques são pedidos para ele**: ele para o que faz, anda até o alvo e só então a ajuda vale. Os pedidos entram numa fila de até 4 (uma plaquinha numerada marca cada alvo) e ele dorme à noite, então à noite o clique só avisa que ele está dormindo.

1. Clique num vaso: ele vem regar (cada pedido cumprido adianta o ciclo; cinco fecham a primeira colheita).
2. Clique na escotilha ou na caixa: abre o cartão da caixa. O botão **Vender** manda ele levar os cestos, que viram sucata (com uma espera curta entre uma troca e outra, mostrada num relógio cinza).
3. Clique numa obra: ele vem martelar e a obra adianta.
4. Junte sucata e compre o **Vaso** extra (o próximo objetivo aparece sempre na faixa de cima).

O bunker é dividido em **cômodos**, cada um com parede, porta e placa: na entrada a **escotilha** (caixa, rádio e a linha de transporte), depois a **horta** (tudo de plantio), a **oficina** (água e energia) e o **quarto** (cama e decoração); a **despensa** fica embaixo da escotilha, e as salas cavadas são a **estufa** (mais horta) e o **quarto dela**. Cada tipo de item só vai no cômodo certo. A janela é uma faixa fixa (344×136 px lógicos); o X no canto fecha o jogo (o primeiro clique pergunta "Sair?", e ele salva sozinho antes de fechar).

Os ciclos são curtos: a batata cresce em 3 minutos, o feijão em 8 e o tomate em 15, e a primeira colheita sai em 2 minutos. Cada máquina tira um clique do seu trabalho: o **gotejador** rega sozinho (os vasos deixam de aceitar pedido) e a **calha** leva os cestos sozinha (a caixa deixa de aceitar pedido). A partir daí o homem toca tudo e você só decide o que construir. A faixa de cima tem uma linha só: **[rosto] Dia N | ⚡ uso/oferta | sucata | ★ meta**. O rosto de Joaquim tem moldura (cinza = tudo bem, âmbar = alguma necessidade pedindo, vermelha piscando = perigo); o raio mostra a energia que ele usa do que tem e fica vermelho e piscando quando falta (o gerador também pisca no bunker); clicar no resto da linha abre a aba Construir, onde o item sugerido vem marcado com uma estrela. O resto aparece no próprio objeto: passe o mouse para ver contorno e uma etiqueta curta, clique em Joaquim (ou no rosto na barra), na caixa, num gerador (ou no raio na barra) ou na antena para abrir um cartãozinho com o estado e a ação. O cartão do Joaquim tem três medidores redondos, **comida, água e sono**, com a porcentagem: ele come, bebe e dorme sozinho. Comida vem dos cestos da despensa (o mesmo estoque que você vende!); água chega sozinha, mas a bomba precisa de energia; sono volta à noite. **Se comida ou água ficarem no vermelho e você vir o aviso, o prazo corre (2 dias sem comida, 1 sem água) e ele pode não aguentar.** Com o jogo fechado o prazo para: ele espera no vermelho até você voltar. Comer ou beber tira do vermelho na hora; sono nunca mata. Ao morrer, a tela de fim mostra os dias vividos, com **Ler o diário** e **Recomeçar**. Os cestos colhidos vão para a **despensa** (o andar de baixo): quanto mais estoque, mais cestos nas prateleiras. Cavar uma sala nova abre um andar embaixo; a janela continua com 2 andares (é uma barra de tarefas): a roda do mouse (Shift+roda para os lados) ou arrastar o chão rola a cena, a câmera segue o Joaquim (e volta uns segundos depois de você rolar à mão) e um mapinha minúsculo, abaixo da alça, mostra onde você está. Ele usa a escada de verdade para ir de um andar a outro, então um pedido pode demorar se ele estiver longe. Tudo que leva tempo usa o mesmo relógio: obra e escavação mostram o círculo com a contagem ("1h48", "45min") o tempo todo; planta só no hover (e um check verde quando está pronta); a espera da caixa também. O selo de cestos aparece em cima da caixa só quando ela está cheia.

## Controles

Tudo é com o mouse.

| Ação | Como |
|---|---|
| Construir, plantar, melhorar a antena | Botão da seta na alça (ou clique na escotilha/caixa): abre a gaveta, aba **Construir**: uma lista só, por nível de antena ("Antena 1" com os itens liberados, depois "Antena 2"... com cadeado e em cinza os que faltam). O botão **Subir** (com o preço) fica fixo no topo e no cabeçalho do próximo nível; clicar na antena do cenário abre a lista nessa seção. Escolha o item, depois o lugar na faixa |
| Ouvir o rádio / ler o Diário | Clique na mesa do rádio ou aba **Rádio** da gaveta (a luz verde pulsa quando há fala nova) |
| Ver o estado (o que Joaquim faz, caixa, energia, antena e jornada da casa) | Clique no próprio objeto: **Joaquim**, **caixa/escotilha**, **gerador**, **antena** (abre um cartão; Esc ou clique fora fecha) |
| Trocar a cultura de um vaso, mover ou desmontar | Clique no objeto na faixa |
| Opções (idioma, áudio, escala, sempre por cima, apagar progresso) | Aba **Opções** ou tela de título |
| Mover a janela | Arraste pela alça (ícone da mão); ela fica dentro da área útil do monitor |
| Recolher | Botão de esconder na alça: a janela vira uma aba pequena na borda de baixo e o jogo continua. Clique na aba para voltar |
| Sempre por cima, resetar posição, sair | Menu do ícone na bandeja do Windows (perto do relógio) |
| Janela sumiu da tela | Menu da bandeja → Resetar posição, ou rode `QuantosDias.exe --reset-window` |

Esc fecha a gaveta ou cancela o posicionamento; com a gaveta fechada, abre as Opções. Fechar o jogo e voltar depois: o tempo passado conta (até 72 h) e a gaveta mostra um resumo do que aconteceu.

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
assets/fonts/            fonte Pixelify Sans e licença
tools/art, tools/audio   geradores Python da arte e do áudio
tools/content            conferência de textos e conteúdo
tools/sim_oracle         simulação da economia em Python (referência do ritmo)
tools/build              ícone e script de export
tests/                   testes headless e run_all.sh
docs/                    design, contratos, roteiro, teste no Windows
```

## Licenças e créditos

- **Jogo, código, design e roteiro:** Vinícius.
- **Fonte:** Pixelify Sans, de Stefie Justprince, sob a SIL Open Font License 1.1. Texto da licença em [`assets/fonts/PixelifySans-OFL.txt`](assets/fonts/PixelifySans-OFL.txt); detalhes em [`assets/fonts/README_fonte.md`](assets/fonts/README_fonte.md).
- **Arte:** pixel art gerada por código pelos scripts de `tools/art/` com paleta fixa; não usa imagens de terceiros. Faz parte do projeto e segue a mesma licença do jogo.
- **Áudio:** efeitos, loops e músicas sintetizados por código pelos scripts de `tools/audio/` (numpy, convertidos para OGG com ffmpeg); não usa gravações de terceiros. A voz dela é um placeholder sintético até a gravação real.
- **Motor:** [Godot Engine](https://godotengine.org), licença MIT. O exe exportado inclui o Godot e as bibliotecas de terceiros dele; os avisos de licença estão em `Engine.get_license_text()` e em https://godotengine.org/license.
- Feito com a ajuda do Claude (Anthropic).
