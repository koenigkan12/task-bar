# Direção de arte: lateral com cômodos de verdade

Aprovada pelo Vncs em 13/10/2026 ("bem melhor isso dos cômodos"). Referência: `mockup_v4_lateral_2_andares_zoom.png` e `comparativo_v4_lateral_atual_vs_nova.png` nesta pasta. O script que gera os mockups é `gerar_mockup_v4_lateral_2_andares.py`.

A vista continua lateral e a superfície fica como está hoje: céu, cidade em ruínas, grama, antena, painel e alçapão.

## O que muda
1. **Cômodos separados.** Uma parede grossa de concreto (6 px lógicos) separa cada cômodo, com uma porta de aço no vão. Cada cômodo tem seu próprio material de parede e de chão e sua própria cor de luz:
   - entrada: concreto, com a escada do alçapão, a caixa de sucata, o cabide e as botas;
   - oficina e rádio: concreto com luz quente, mapa da cidade com marcações, calendário riscado, tracinhos contando os dias e quadro de ferramentas na parede;
   - estufa: azulejo claro com tom verde e lâmpadas de cultivo de luz magenta;
   - quarto: lambri de madeira na metade de baixo, chão de tábua, tapete, fotos dela e calendário.
2. **Coisas no seu lugar.** Prateleiras, quadros e objetos ficam presos na parede. Canos e fios correm pelo teto e atravessam todos os cômodos.
3. **Dois andares (proposto, ainda não confirmado).** Um segundo andar fica embaixo, ligado pelo poço da escada: despensa com latas e caixas etiquetadas e um cômodo em escavação com escoras de madeira. O resto é terra com pedras e raízes. Como progressão, cavar cômodos novos para baixo. A faixa passa de 88 para cerca de 126 px lógicos (252 px na tela em 1080p).
   - Alternativa: um andar só, com os itens 1 e 2, mantendo os 88 px.

## Medidas usadas no mockup (px lógicos)
- superfície: 26
- laje: 6
- interior do andar: 37 (o personagem tem cerca de 30)
- chão: 5

## Como ficou no jogo
- Faixa de 136 px lógicos (272 px na tela em 1080p com escala 2), com 2 andares. Código em `scripts/view/bunker_terrain.gd` (fundo), `bunker_decor.gd` (enfeites por código na paleta fixa) e `bunker_geo.gd` (medidas; o andar B é o A deslocado em 51 px).
- O andar de baixo é cenário por enquanto: despensa sob a sala 1 e escavação com escoras sob a sala 2. Escavar sala nova continua para o lado; tornar o andar de baixo jogável é um passo futuro.
- Materiais por sala: 1 concreto quente, 2 azulejo com luz de cultivo, 3 lambri e piso de tábua. A cama continua na sala 1 (cantinho de dormir com lambri).
