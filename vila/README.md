# Quantos Dias? Vila (protótipo)

Primeiro pedaço jogável da versão "assentamento" (design em `/mnt/project-files/bunker/descricao-do-jogo.md`).
Projeto Godot 4.6 separado do jogo do bunker (que continua na raiz do repositório), para os dois não se atrapalharem.

**O que tem:** vista de cima numa janela de canto (1152×648 (3×; 2× em tela pequena), sempre por cima), zoom em 3 degraus e arrastar;
torre do rádio níveis 1 a 3 (o 3 ainda não libera nada); 8 prédios (poço, horta, depósito, barraco, casa,
fogueira, serraria, ferro-velho) com nível 2 de horta e depósito; pessoas autônomas que andam, constroem,
cortam lenha, catam sucata e levam tudo ao depósito; seu Ari chega na torre 2; depois, grupos de 3 no portão
com passivas de raridade aleatória (escolha 1 ou ninguém); comida e água consumidas por pessoa;
noite das 22h às 6h (todos dormem); offline a 20% com limite do depósito e resumo ao voltar; save automático.

**Fora deste pedaço:** tutorial guiado, mercador e praça, peças/oficina/energia, modo gestão (janela grande),
áudio, Opções.

## Rodar
```
bash Ferramentas/godot.sh --path vila                    # da raiz do repositório
bash ../Ferramentas/godot.sh --path . -- --fresh --hour=20 --speed=30   # de dentro de vila/: começa do zero, 20h, 30x
```
Argumentos de teste (depois de `--`): `--fresh`, `--hour=H`, `--speed=N`, `--demo=MIN` (joga sozinho antes de mostrar),
`--open=build|tower|gate|person|place`, `--shot=arquivo.png`. Com algum deles o save de verdade não é sobrescrito.

## Testes
```
godot --headless --path vila --script res://tests/sim_test.gd
godot --headless --path vila --script res://tests/ui_flow_test.gd -- --fresh --hour=10
```

## Arte
Toda original, gerada por `tools/gerar_arte.py` (Pillow), imitando o clima dos pacotes Stranded do penusbmic
(que são pagos e não estão aqui). Se comprar os pacotes, os PNGs de `assets/art/` podem ser trocados mantendo
nomes e tamanhos.
Fonte: DotGothic16 (OFL, `assets/fonts/`), em 8 px lógicos (16 px na tela): é o tamanho de desenho dela.
