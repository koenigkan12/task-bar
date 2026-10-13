# Bunker — Análise de Design (sistêmica + game design)

> Nome provisório: *Quantos Dias?* (ver seção 12). Base: `conceito-jogo-bunker.md`.
> Este documento **não implementa nada**. É uma leitura crítica do conceito: como o jogo funciona como sistema, onde há buracos, o que ainda não foi pensado e o que recomendo decidir antes de abrir a engine.
> Números de economia vêm de uma simulação simples (`Ferramentas/economia_sim.py`, saída em `Ferramentas/saida_economia_sim.txt`). É um **modelo**, não medição: serve para achar estrutura e ordem de grandeza, e tem que ser refeito com o jogo real.
> Marcas nas ideias novas: **[reusa]** só usa o que já existe · **[conteúdo]** pede texto/arte/som novo · **[sistema]** pede regra nova · **[personagem]** pede personagem novo (nenhuma proposta aqui pede isso).
> Respeita o que o conceito pede: escopo pequeno, pé no chão, cozy, "pra quê?" em cada mecânica, e **nada da lista de ideias descartadas**.

---

## 0. O que decidir primeiro (resumo)

| # | Decisão | Recomendo | Por quê, em uma linha |
|---|---|---|---|
| 1 | Formato da janela | **Janela-faixa opaca, grudada no rodapé da área útil, que cresce para o lado quando ele escava**; faixa transparente de ponta a ponta fica para depois | Transparência depende de driver/compositor e custa performance (docs do Godot); o Rusty's tem bug real de janela que some em multimonitor. Um bunker em corte é naturalmente um retângulo de terra. Decide com um teste técnico curto (seção 5.9) |
| 2 | "Ordem permanente" e o tempo do homem | Plantar vira configuração do vaso ("sempre feijão"), não ação repetida. O **tempo dele é o recurso escondido** da economia | Sem isso o jogo não é idle (a crítica nº 1 ao Rusty's é "não é idle de verdade no começo") e a história "ele corre → fica em paz" não tem base |
| 3 | O que acontece com o jogo fechado | **Progresso offline sim**, com o mesmo código do online, + **Diário do rádio** que conta o que ele ouviu enquanto você não olhava | Na simulação, quem só joga das 9 às 18h leva **25 dias** sem offline e **15 com offline** para chegar ao fim do MVP; o diário resolve "só jogo no trabalho e nunca vejo a noite" |
| 4 | A esposa chega? | **Sim, na versão 1.0, fora da tela**, e o jogo continua num epílogo. O "pós-contato" vira uma **jornada finita (uma lista de coisas da casa)**, não um "para sempre" | Pagar 14+ dias de espera sem desfecho é risco de avaliação ruim; chegar fora da tela respeita a regra "ela nunca aparece" |
| 5 | Duração e ritmo | Alvo do MVP: **~14 dias de relógio** até a antena 5; 30 dias ≈ preços ×2,3. A **escotilha** (transporte + rádio) é o gargalo de renda e metade das compras não paga em dinheiro | Ver seção 3. Tem que decidir *em que moeda* cada compra paga, senão vira "clicar na próxima melhoria" |

Sugestão de **o que não fazer ainda**: o protótipo HTML (seção 10.6) e gerar arte em lote.

---

## 1. Pilares e filtro de decisão

Três frases para testar qualquer ideia nova. Se a ideia quebra uma, ela sai.

1. **Esperar é o jogo.** Nada exige você; tudo responde a você. (Sem sequência diária de login, sem recompensa por voltar, sem contagem regressiva que castiga.)
2. **Cada coisa é feita de lixo e tem cara de gambiarra.** A engenhoca é a recompensa visual; não há "item" que apareça do nada.
3. **O silêncio também é conteúdo.** O que ele faz quando ninguém manda (ler, cochilar, olhar a foto) e o que o rádio diz quando você não está olhando são tão importantes quanto o que você compra.

Anti-pilares (já implícitos no conceito, escritos para não esquecer): não punir (sem morte, sem perda, sem estrago por ausência); não pedir atenção (sem som, sem notificação do sistema por padrão); não explicar com texto o que dá para mostrar.

---

## 2. Estrutura de loops (lente 1)

### 2.1 Os três tempos

| Escala | O que acontece | O que o jogador faz | O que ele sente |
|---|---|---|---|
| **Momento** (segundos a minutos) | Ele planta, rega, carrega o cesto, martela, pedala. Quando está livre: lê, cochila, ouve. | Olha. Às vezes passa o mouse e clica em algo. | Companhia. "Está vivo." |
| **Sessão** (check-in de ~2 min, 1 a 3 por dia) | A escotilha vendeu; a rádio pode ter um recado novo; acumulou sucata. | Abre a gaveta de gestão, escolhe **uma** coisa (comprar/posicionar/decorar/trocar cultura), fecha. | Pequeno progresso e uma pergunta ("o que vem agora?"). |
| **Meta** (dias) | Cada nível de antena traz uma voz e libera máquinas. | Escolhe a ordem de crescimento; decide onde cabe cada coisa. | Arco: solidão → contato → esperança → reencontro. |

Regra de projeto que sai disso: **a unidade de decisão é uma por check-in**. Com ~18 compras no MVP em ~14 dias, a média é de pouco mais de 1 compra por dia. Está bem para o tom. Mas implica que cada compra tem de importar e que, entre compras, o jogo precisa ter *conteúdo* (rádio programada, seção 6.3) e *vida* (comportamentos dele).

### 2.2 Onde há escolha de verdade e onde é só "clicar na próxima"

| Decisão | Escolha real? | Comentário |
|---|---|---|
| Qual cultura em cada vaso | **Sim**, desde a antena 2 | Valor vs ciclo vs trabalho. Vira interessante com as ordens permanentes (2.3). |
| Ordem das 4 primeiras melhorias baratas | **Sim** | A simulação mostra que as ordens razoáveis ficam dentro de ~10% de diferença entre si (3.6): o jogador pode errar sem se arrepender. |
| Onde cada coisa fica (distância até a escotilha, cômodo) | **Sim**, se a distância custar tempo dele (3.3) | É o "layout" do Rusty's traduzido: aqui, o que importa é o quanto ele anda. |
| Decorar vs produzir (espaço) | **Sim**, mas só enquanto o espaço apertar (3.7) | Depois do 3º cômodo o aperto some, e o pós-contato é quase todo decoração. Precisa de função própria (6.4). |
| Comprar a antena já vs juntar economia | **Parcial** | Rushar a antena **não** é dominante: é uma armadilha lenta (3.6). Bom: a escolha existe e o "errado" não trava. |
| "Comprar o próximo da fila" nas linhas de água, energia e escavação | **Não**, a menos que algo vire visível | Metade das compras não aumenta renda (3.4). Elas precisam pagar em *outra moeda*, e o jogador precisa *ver* essa moeda. |

### 2.3 Buraco central do conceito: o jogo só é idle se as ordens forem permanentes

O conceito diz: "quando o jogador dá uma ordem, ele larga o que está fazendo e obedece (plantar, construir, decorar)". Se **plantar** é uma ordem de uma vez só, então depois de colher o vaso fica vazio até alguém mandar de novo: a economia para quando você sai. O Rusty's tem exatamente essa crítica nas avaliações ("não é idle de verdade no começo, plantar e colher pedem input até a automação chegar").

**Recomendo (tipo [reusa], não cria sistema):** a ordem de plantio é uma **configuração do vaso** ("este vaso: feijão, sempre"). Ele replanta sozinho. As ordens "de uma vez" ficam só para o que é de uma vez: construir, mover, decorar. Assim:
- o jogo roda sem você desde o minuto zero;
- o que as máquinas automatizam passa a ser *tarefas* (regar, carregar, pedalar), não "ter que mandar plantar";
- o primeiro clique do jogador (seção 7) é configurar um vaso.

---

## 3. Economia como sistema (lente 2)

### 3.1 Mapa: fontes, conversores, limites

```
                 ┌─────────── LIMITES (não são dinheiro) ───────────┐
                 │  ENERGIA  (oferta do gerador ≥ consumo)          │
                 │  ESPAÇO   (slots dos cômodos)                    │
                 │  TEMPO DELE (16 h acordado/dia)  ← escondido     │
                 └───────────────────────────────────────────────────┘

 semente ──► VASO/CANTEIRO/PRATELEIRA/ESTUFA ──► cesto (comida)
              (plantio: quantos "vasos" e que cultura)   │
                 ▲ água (regar: tarefa ou automático)     │ ele come ~3/dia (ralo pequeno)
                 ▲ energia (luz da estufa, bomba)         ▼
                                              CAIXA DA ESCOTILHA
                                         (vazão = visitas/dia × capacidade)
                                                          │  ◄─ ANTENA define visitas/dia
                                                          │  ◄─ TRANSPORTE define capacidade
                                                          ▼
                                                      SUCATA
                       ┌──────────────┬──────────────┬────┴───────┬──────────────┐
                       ▼              ▼              ▼            ▼              ▼
                  máquinas      escavar       antena (nível)   decoração      (nada se perde:
                  (4 linhas)    (espaço)      = história       (vida dele)     desmontar devolve)
```

**Equação central** (a única que importa para a renda):

> **renda/dia = mínimo( produção/dia , visitas/dia × capacidade da caixa ) × preço do cesto**

- *produção* = quantos vasos × quanto rende a cultura × quanto ele consegue cuidar;
- *visitas/dia* sobe com a **antena** (a caravana do nível 3 dobra a frequência);
- *capacidade da caixa* sobe com o **transporte** (balde → calha → roldana → esteira);
- *preço do cesto* sobe com a **cultura** (batata → feijão → tomate), que também vem da antena.

### 3.2 Os cinco limites, o sintoma visível e o remédio

Princípio de design: **cada limite tem um sintoma que dá para ver sem número e um único tipo de compra que o resolve**. Assim o jogador diagnostica olhando, que é a graça de "ver a maquininha".

| Quando o gargalo é... | O jogador vê... | Resolve com... |
|---|---|---|
| **Escotilha** (vendo menos do que produz) | A caixa transborda; cestos empilhados fora dela | Transporte (capacidade) ou antena (visitas) |
| **Tempo dele** | Ele nunca descansa; tarefas acumuladas; vasos esperando | Água, transporte, energia (cada uma tira uma tarefa) |
| **Produção** | Vasos vazios ou pouca coisa crescendo; ele descansa | Plantio (mais vasos, melhor cultura) |
| **Energia** | Luzes piscando; construção bloqueada ("falta energia") | Gerador (bicicleta → moinho → bateria → painel) |
| **Espaço** | Não cabe mais nada no cômodo | Escavar |

Na simulação esses gargalos **se alternam** ao longo do jogo (seção 3.5), que é o comportamento certo para um jogo de melhorias.

### 3.3 O tempo do homem (recurso escondido) e a história sem texto

O conceito quer: no início ele corre o dia todo; depois as máquinas trabalham e ele fica em paz. Isso é **economia de tempo dele**, e dá para modelar sem criar sistema novo:

- Ele tem ~16 h acordado por dia. Cada ciclo de um vaso consome tempo dele: plantar e colher (~3 min), regar (~5 min, se não for automático), carregar até a escotilha (6 min de balde, 3 de calha, ~1 de roldana, ~0 de esteira), e pedalar enquanto o gerador for a bicicleta (~25% do dia).
- Se a soma passa de 16 h, a produção cai na proporção. Esse é o estado "trabalho" da tabela 3.2.
- Cada linha de serviço (água, transporte, energia) **tira uma tarefa**. No fim, só sobra plantar e colher.

Duas observações importantes:

1. **Os tempos de tarefa não são números a escolher: saem da distância.** No Godot, regar = andar da cisterna ao vaso, encher, voltar; carregar = ir até a escotilha. Quem define a duração é o *layout dos cômodos* e a velocidade de caminhada. Isso é o que faz o posicionamento importar sem criar sistema nenhum (3.7).
2. **A curva "ocupado → livre" não é automática.** Na simulação, a fração ocupada fica em ~77% e 73% nas antenas 1 e 2 e **sobe para ~97%** nas antenas 3 e 4, porque a compra que mais rende (prateleira e depois estufa) aumenta o número de vasos antes de comprar a água e o transporte que o aliviam. Para o visual "ele vai ficando em paz" funcionar, as melhorias de serviço têm que chegar **antes** das de densidade, ou o preço delas tem que empurrar nessa ordem. Alvo sugerido de "tempo ocupado" por nível de antena: **90 → 80 → 65 → 45 → 30%** (a calibrar).

Estado "faminto": o conceito diz "triste e lento". Recomendo **piso de 60% da velocidade** e nada de espiral (menos comida → mais lento → menos comida). É só um multiplicador e um balão de pensamento com o ícone de comida [reusa].

### 3.4 Estrutura do MVP em uma grade (e o que cada compra paga)

O MVP do conceito (≈12 construções, 5 níveis de antena, 3 cômodos) fecha numa grade limpa:

> **4 linhas de serviço × 3 melhorias = 12 construções** (a primeira etapa de cada linha já existe no início: vaso, lata, bicicleta, balde) **+ 2 escavações + 4 melhorias de antena = 18 compras**, mais ~5 itens de decoração.

| Linha | Etapa 0 (começa com) | Etapa 1 | Etapa 2 | Etapa 3 |
|---|---|---|---|---|
| **Plantio** | vaso (1 vaso) | canteiro (3) | prateleira de cultivo (5) | estufa (6, só tomate) |
| **Água** | lata (ele rega) | gotejador PET (4 vasos) | cisterna (10) | bomba (todos) |
| **Energia** | bicicleta (oferta 3, ele pedala) | moinho no duto (5) | bateria de carro (8) | painel na escotilha (12) |
| **Transporte** | balde (6 min/ciclo, caixa 14) | calha (3 min, 22) | roldana (1 min, 34) | esteira (≈0, 50) |
| Escavação | cômodo 1 | cômodo 2 | cômodo 3 | — |
| Rádio | antena 1 | 2 | 3, 4, 5 | — |

**Regra "pra quê?" aplicada a cada compra.** Toda compra tem que pagar em **pelo menos uma** destas cinco moedas, e o jogador tem que conseguir ver qual:

| Moeda | O que ela é | Compras que pagam nela |
|---|---|---|
| Renda | mais sucata/dia | vaso, canteiro, prateleira, estufa, calha, roldana, esteira, antenas 2 e 3 (visitas, feijão) |
| Tempo dele | ele fica livre | gotejador, cisterna, bomba, moinho, painel (e calha/roldana/esteira também) |
| Espaço | cabe mais coisa | escavações |
| Porta (pré-requisito) | libera a próxima | bateria, moinho, painel, cômodo 3 (exigidos pelas antenas 4 e 5) |
| História/vida | voz nova, comportamento novo | antenas, decoração |

Resultado da simulação (plano equilibrado, 19 compras até a antena 5): **10 aumentam a renda em mais de ~5 sucata/dia; as outras 9 não**. Isso não é defeito se elas pagam em outra moeda *visível*; é defeito se o jogador só sente "gastei e nada mudou". Remédio de baixo custo [reusa]: cada compra de serviço muda **a rotina visível dele** (a primeira vez que o gotejador funciona, ele para de carregar a lata; o moinho para a bicicleta).

### 3.5 Curva de custos: primeiro esboço

Preços em sucata, arredondados da simulação (plano **equilibrado**: compra os baratos que sobem a renda e sobe a antena assim que o gerador e os cômodos permitem). Isso é a versão de **~14 dias**.

| Compra | Preço | Libera com | Consome energia | Dia no plano | Renda/dia depois |
|---|---|---|---|---|---|
| vaso extra (×2) | 6 | início | 0 | 0,5 e 0,8 | 29 → 36 |
| **Antena 2** (homem das sementes) | **50** | gerador ≥3 | rádio 1 | **2,4** | 57 (feijão) |
| moinho | 50 | início | — | 3,4 | 57 |
| canteiro (×2) | 30 | início | 0 | 3,5 / 3,8 | 75 |
| calha | 40 | início | 0 | 4,4 | 118 |
| gotejador | 40 | início | 0 | 4,5 | 118 |
| cômodo 2 | 85 | início | 0 | 5,4 | 118 |
| **Antena 3** (caravana: visitas ×2) | **110** | gerador ≥5 | rádio 2 | **6,4** | 132 |
| prateleira de cultivo | 110 | antena 3, cômodo 2 | 0 | 6,5 | 185 |
| bateria de carro | 130 | antena 3 | — | 7,5 | 185 |
| **Antena 4** (velho da música; tomate) | **240** | gerador ≥8, cômodo 2 | rádio 2 | **8,5** | 185 |
| cisterna | 150 | antena 2, cômodo 2 | 0 | 9,5 | 192 |
| estufa (tomate) | 270 | antena 4, cômodo 2 | 2 | 10,5 | 243 |
| roldana | 120 | antena 3, cômodo 2 | 0 | 11,4 | ~297 |
| cômodo 3 | 210 | antena 3 | 0 | ~11,8 | 297 |
| painel na escotilha | 320 | antena 4, cômodo 3 | — | ~13,4 | 297 |
| **Antena 5** (a voz dela) | **450** | gerador ≥12, cômodo 3 | rádio 3 | **14,5** | ~300 |
| bomba · esteira (pós-contato) | 360 · 300 | antena 5, gerador ≥8 | 2 · 2 | depois | — |

- Sucata gasta até a antena 5: ~2.500; tudo junto: ~3.100. O maior preço é 450: continua em "centenas", como o conceito pede.
- A renda sobe de ~30 a ~300/dia: o jogador que volta no fim do dia vê dezenas a poucas centenas na mão, tudo em escala humana.
- Os **pré-requisitos de energia e cômodos nas antenas 4 e 5** (gerador ≥8 e ≥12) servem para **espaçar os marcos da história** (dias 2,4 · 6,4 · 8,5 · 14,5) sem mexer no preço da antena. É o botão certo: preço controla duração, pré-requisito controla espaçamento.
- **O botão de duração funciona, como o conceito diz**: multiplicando todos os preços, a antena 5 chega no dia **14,5 (×0,7)**, **20 (×1,0)**, **32 (×1,6)**. Para ~30 dias: preços ×1,6 sobre a tabela-base da simulação (= ×2,3 sobre a tabela acima; a simulação dá 32 dias).
- **Dois buracos de ritmo** que o esboço mostra e que precisam de conteúdo: dias 2,4 → 6,4 (4 dias) e 8,5 → 14,5 (6 dias) sem voz nova. A rádio programada (6.3) existe para preencher isso.

### 3.6 Estratégias dominantes, armadilhas e becos sem saída

Resultados da simulação (preços ×0,7):

| Estratégia | Antena 5 em | Leitura |
|---|---|---|
| Equilibrada (barato que rende + antena assim que possível) | **14,5 dias** | referência |
| Variante "densa" (estufa antes da prateleira) | 15,5 dias | ~7% pior: nenhuma ordem razoável é muito melhor que outra |
| Economia primeiro, antena por último | 18,5 dias | 28% pior |
| **Antena primeiro** (só antena e o que ela exige) | **32,8 dias** | **armadilha lenta**, 2,3× pior |

- **Não há estratégia dominante entre as razoáveis.** Bom.
- **Rushar a história é uma armadilha** (não um beco): o jogador que compra só antena fica com ~35 sucata/dia nas três primeiras semanas e leva mais de um mês. Quem quer ouvir a voz logo é justamente quem mais se frustra. Mitigação [reusa]: as exigências de gerador/cômodos das antenas já empurram para construir; e a **rádio programada** (6.3) dá conteúdo mesmo sem comprar. Alternativa se incomodar: atenuar o preço da antena quando a renda está baixa. Decisão para o playtest, não agora.
- **Beco sem saída: não encontrei**, com estas travas de projeto (todas são regras de design, não de código):
  1. Sementes **não custam sucata** (cultura nova vem por conhecimento, via rádio). Sempre dá para plantar.
  2. Os vasos iniciais **não podem ser vendidos/demolidos**; o resto pode ser **desmontado devolvendo 100%** (cozy: sem arrependimento) e **movido de graça** (custa só o tempo dele).
  3. Comida baixa = lento (piso de 60%), nunca zero.
  4. Máquinas que consomem energia **não podem ser construídas sem oferta livre** (o limite é checado na compra, não em tempo real). Assim não existe micro-gestão de liga/desliga e não existe estado "gastei tudo e apagou".
  5. Checagem automática do grafo de pré-requisitos no script: tudo é alcançável com sucata infinita, sem ciclos (`grafo()` em `economia_sim.py`).
- **Alertas de projeto que a simulação não pega:** a decoração não rende nada, então um jogador otimizador nunca decora; o pós-contato precisa dar função a ela (6.4). E a água do conceito aparece como "linha" mas não como "recurso": recomendo tratá-la como **serviço com capacidade** (gotejador serve 4 vasos, cisterna 10, bomba todos), sem estoque de litros.

### 3.7 Espaço como quebra-cabeça

Proposta inicial: cômodos de **6, 8 e 8 slots** (22 no total).

| Ocupa slots | Quanto |
|---|---|
| Fixos | cama 1, caixa da escotilha 1, mesa do rádio 1 |
| Serviços (uma instância por linha, a evolução **substitui**) | água 1→1→2→2, energia 1→2→2→0 (painel fica na escotilha), transporte 0→1→1→2 |
| Plantio | vaso 1 slot/1 vaso, canteiro 2/3, prateleira 2/5, estufa 3/6 |
| Decoração | 1 cada (poltrona, estante, mesinha, foto...) |

Estado final aproximado: ~9 slots de fixos+serviços, ~9 de plantio, ~4 de decoração: **não cabe tudo** e o jogador precisa escolher entre mais vasos, mais conforto e escavar mais um cômodo... até o 3º cômodo, quando o aperto acaba. O pós-contato pede mais decoração, então **um 4º cômodo opcional pós-contato** (o "quarto dela") dá espaço para a fase "preparar a casa" e é conteúdo, não sistema.

Regra de ouro: **evolução substitui e cresce** (1→2→3 slots). Isso cria pressão de espaço *sem* regras de adjacência nem de bloqueio.

---

## 4. Modelo de tempo para um idle (lente 3)

### 4.1 O que "um dia" significa
O conceito mistura duas coisas: "ele come um pouco por dia" e "dorme de noite seguindo o horário real". Recomendo fixar: **1 dia de jogo = 1 dia de relógio**, fuso do jogador, e **as 10 a 30 "dias" de duração são dias de calendário** (não de tela). A simulação usa 06:00–22:00 acordado e 8 h de sono.

### 4.2 Offline: sim, com o mesmo código
Quanto o offline pesa (jogo "ligado" das 9 às 18h, 3 check-ins; preços ×0,7):

| Caso | Antena 5 em |
|---|---|
| Bunker produz o dia inteiro (offline completo) | **14,7 dias** |
| Só produz com o jogo aberto, 9–18h (sem offline) | **25,4 dias** (+73%) |

Sem offline, o jogador que fecha o jogo para jogar outro título ou desliga o PC à noite **é punido** — exatamente o contrário do tom. Recomendação:

- O estado do bunker avança por **tempo de relógio** (`Time.get_unix_time_from_system()` guardado no save), em passos grossos (ex.: 10 min), com **o mesmo código** usado com o jogo aberto. Nada de "fórmula de offline" separada (é onde nascem os bugs).
- Teto prático: 72 h (cobre um fim de semana). O próprio limite da caixa da escotilha já trava o acúmulo.
- **Nada piora ausente**: sem estrago, sem fome extra, sem punição (anti-pilar). Decisão posterior do autor (13/10): comida e água podem matar, mas só **depois que o jogador viu o aviso vermelho com o jogo aberto**; com o jogo fechado o prazo para e ele espera no vermelho (ver 7.2).
- Ao voltar, não mostrar uma janela de resumo "bônus": mostrar **linhas no Diário** (4.4). É mais coerente e mais bonito.
- Detalhes de robustez: relógio do PC que volta no tempo (ignorar o delta negativo), horário de verão, suspensão/hibernação (a retomada cai no mesmo caminho do offline), salvamento **atômico** (escrever arquivo temporário e renomear) porque o jogo roda o dia todo e o PC pode desligar a qualquer momento.

### 4.3 Dia/noite com relógio real (e quem só joga no trabalho)
O conceito quer que ele durma de noite pelo horário real. Quem joga só das 9 às 18h nunca vê a noite. Soluções, da mais barata:

1. **O Diário conta a noite** [conteúdo pequeno, reusa as linhas do rádio]: "Esta noite ele dormiu. Às 3h o rádio pegou uma voz."
2. **O relógio do bunker é a luz que desce pelo duto da escotilha** [reusa]: o bunker é subterrâneo e não tem janela, então a única forma realista de saber a hora é a luz que entra pela escotilha (e o relógio de parede, se comprarem). É um degradê, não arte nova.
3. **O rádio tem programação por horário real**, com pelo menos duas janelas dentro do expediente (≈12h30 e ≈17h30) e as melhores à noite (o rádio de verdade pega melhor à noite, o que é pé no chão); tudo cai no Diário.
4. O sono dele é flexível dentro de 22h–6h; não amarrar a uma hora exata.

### 4.4 Diário do rádio [conteúdo pequeno + UI]
Uma lista, na gaveta, com cada fala já ouvida (as ~30 do conceito) e "o que ele fez enquanto você estava fora" (3 a 5 linhas curtas). É o que permite: rever uma fala que passou rápido; ler a história sem som; e saber o que perdeu quando o jogo estava fechado. Também é o lugar natural para a legenda da voz dela (seção 8).

### 4.5 Cadência de check-in e sinais de atenção
Resultado da simulação: o jogo é **tolerante à cadência**. A antena 5 chega em **15,8 dias com 1 check-in por dia**, 14,5 com 3 e 14,4 com 8 (~10% de diferença entre o mínimo e o máximo). Quem olha uma vez por dia perde pouco; quem fica clicando o dia todo não ganha vantagem.

Sinais de que "algo precisa de você", sem encher:

| Sinal | Onde | Quando |
|---|---|---|
| Luz verde de mostrador pulsando no rádio | rádio | tem fala nova não lida |
| Caixa da escotilha cheia/transbordando | escotilha | a escotilha é o gargalo |
| Balão de pensamento dele com o ícone do **próximo objetivo** brilhando | sobre ele | o objetivo que você fixou no quadro de avisos está pago [sistema pequeno: fixar 1 objetivo] |
| Luz piscando | teto | falta energia para algo planejado |

Regras anti-nag: **sem som, sem notificação do Windows (opcional e desligada por padrão), no máximo um elemento pulsando por vez, cada sinal para quando você passa o mouse e só volta com evento novo.** Reservar **uma cor** da paleta (sugestão: verde de mostrador de rádio) *só* para sinais; o resto do mundo (ferrugem, concreto, lâmpada) nunca usa essa cor. A paleta fixa de 16–24 cores do conceito faz isso virar regra checável por script.

---

## 5. A faixa na tela: UX e técnica em Godot (lente 4)

Fatos abaixo vêm da documentação oficial do Godot (branch `master`, consultada em out/2026; **conferir na versão que formos usar**). O que não consegui confirmar está marcado.

### 5.1 O que o Godot oferece (confirmado nos docs)

| Necessidade | API | Notas dos docs |
|---|---|---|
| Janela sem borda | `WINDOW_FLAG_BORDERLESS` | Windows, macOS, Linux. |
| Sempre por cima | `WINDOW_FLAG_ALWAYS_ON_TOP` | Windows, macOS, X11. Ignorado em tela cheia. |
| Fundo transparente | `WINDOW_FLAG_TRANSPARENT` + `display/window/per_pixel_transparency/allowed` + `rendering/viewport/transparent_background` | **"Disponibilidade pode variar com driver de GPU, gerenciador de janelas e compositor."** A própria configuração diz que **afeta performance**. |
| Clique atravessando | `window_set_mouse_passthrough(polygon)` / `Window.mouse_passthrough_polygon` | **No Windows, a parte da janela fora do polígono não é desenhada**; em Linux (X11) e macOS é. É polígono, não por pixel. |
| Não roubar o foco | `WINDOW_FLAG_NO_FOCUS` | A janela ignora todo input, exceto cliques de mouse. Útil para a faixa não tirar o foco do que você está fazendo. |
| Área útil (sem a barra de tarefas) | `DisplayServer.screen_get_usable_rect(screen)` | Windows, macOS, X11. |
| DPI/escala | `screen_get_scale`, `screen_get_dpi` | No Wayland a escala só é exata para a tela da janela principal; no macOS o DPI é impreciso com escala fracionada. |
| Ícone de bandeja | nó `StatusIndicator` | **Só Windows e macOS.** |
| Reduzir uso | `Engine.max_fps`, `OS.low_processor_usage_mode(_sleep_usec)` | Com vsync ativo, o FPS máximo não passa da taxa do monitor. O modo de baixo processamento "é para editores/mobile; para a maioria dos jogos, deixe desligado". |

**Não existe, nos docs, um flag "sempre atrás de todas as janelas".** Colar a janela no fundo (`HWND_BOTTOM` no Windows) exigiria código nativo (extensão); **não encontrei plugin pronto e não verifiquei**. Alternativa sem código nativo: janela normal, *não* sempre-por-cima. Se a faixa fica na borda inferior e as outras janelas maximizadas cobrem a área útil, ela some atrás delas, que é o efeito "atrás das janelas" que o conceito pede, e volta quando você clica nela na barra de tarefas.

### 5.2 Decisão de forma: janela opaca que cresce

A pergunta em aberto do conceito é "faixa embaixo da tela ou janela no canto". Recomendo um **meio-termo**:

- **Janela retangular opaca**, ancorada no rodapé da **área útil** (acima da barra de tarefas, nunca sobre ela), com **arrasto livre** e botão de recolher.
- **A largura cresce quando ele escava** (1 cômodo estreito → 3 cômodos largos). Isso conta a história visualmente ("começa quieto e vira engenhoca") e **dispensa transparência e polígono de clique**: o corte do bunker é um retângulo de terra.
- Faixa de ponta a ponta com transparência fica como **opção de polimento** *depois* do teste técnico, porque concentra os três maiores riscos (driver/compositor, custo de GPU, clique por polígono + "não desenha fora" no Windows).
- Modos de exibição que o mercado já ensinou a esperar (o *Desktop Island* anuncia tela cheia, rodapé, janela flutuante e só notificações): comece com **rodapé + janela flutuante** (são o mesmo objeto, só muda a âncora).

Proporção sugerida (a calibrar): tela lógica de **~80 px de altura** (16 px de superfície com o mastro da antena que cresce a cada nível + 64 px de cômodos) e **160 px de largura por cômodo**; escala **inteira** (×2 em 1080p, ×3 ou ×4 em telas maiores), `stretch mode = viewport`, `scale mode = integer`. Em 1080p isso dá ~160 px de altura (≈15% da tela) e ~960 px de largura com três cômodos. Personagem de 32 px cabe em cômodo de 64 px com uma lâmpada no teto.

### 5.3 Janela pequena não tem lugar para interface
Armadilha escondida: por padrão `display/window/subwindows/embed_subwindows = true`, ou seja, tooltips, menus e popups ficam **dentro** da janela principal. Uma janela de 160 px de altura recorta qualquer tooltip. Soluções:

1. **Gaveta (recomendada):** clicar numa área do bunker faz a janela **crescer para cima** (animação de ~0,2 s), mostra o menu de construção/antena/Diário e **volta ao tamanho** quando você termina. É o "check-in de 2 minutos" em forma de UI. [reusa, só UI]
2. Subjanelas nativas (`embed_subwindows = false`): funciona, mas cria janelas de sistema para cada popup e é mais lento. Deixar de plano B.

### 5.4 Posição, multimonitor, DPI: o bug do Rusty's como lição
Nos fóruns do Rusty's há relato de que a opção "sempre por cima" às vezes **manda a janela para fora de todos os monitores** (uma vez completamente fora, e o menu de opções ficou inalcançável; a posição é salva e reaparece na reabertura). A solução deles foi teclas "R"/"T" para resetar. Para nós:

- Ao abrir, **validar** que o retângulo salvo intersecta algum monitor atual; senão, reposicionar no rodapé do monitor principal.
- Guardar posição **por monitor** (identificador + posição relativa) e escala; tratar `size_changed` ao arrastar entre telas com escala diferente.
- Botão "Resetar posição" **sempre alcançável**: menu do ícone da bandeja (Windows/macOS), atalho com a janela focada, e `--reset-window` na linha de comando.
- Barra de tarefas com **ocultar automático**: a área útil vira a tela inteira, então a faixa fica na borda; a barra, quando aparece, cobre a faixa. Aceitável.
- Atalho global (esconder com a janela sem foco): **o Godot não tem API de atalho global** (não encontrei na documentação); precisa de código nativo. Sem isso, o "botão de esconder" é um botão na própria faixa + o ícone da bandeja.

### 5.5 Custo de CPU/GPU/bateria (o risco que mais vai importar no dia a dia)
O Rusty's tem relatos de uso alto de CPU/GPU em segundo plano e de queda de FPS no modo de transparência "colorkey" (o recomendado é "alpha"). Para um jogo que roda o dia todo:

- **Simulação desacoplada da renderização.** A lógica (economia, relógio, save) é código puro que avança por `advance_to(tempo)` em passos de 1 s a 10 min; a cena só desenha o estado. Isso serve ao online, ao offline, ao teste e ao "demo acelerado" (10.4).
- **FPS baixo de propósito:** a arte é pixel art animada a 8–12 quadros/s; renderizar a **12–15 FPS** (`Engine.max_fps`) é visualmente idêntico e corta o consumo a menos da metade do padrão de 60. Cair para **~5 FPS** quando o mouse não está sobre a janela e ela não tem foco; **~1–2 FPS** em "modo economia" (botão e/ou bateria); só a lógica rodando quando recolhido.
- Renderizador **Compatibility**, 2D puro, sem MSAA, sem sombras dinâmicas; resolução lógica pequena (ela é escalada pela GPU).
- `display/window/energy_saving/keep_screen_on = false` (o padrão do jogo não pode impedir a tela de apagar).
- **Oclusão:** o Godot não sabe que sua janela está coberta por outro app em tela cheia; mesmo assim ela continuaria renderizando. Mitigação: o FPS baixo acima e um "modo economia" fácil de achar. Se isso incomodar nos testes, vira ponto de código nativo.
- Metas de aceitação (**hipóteses a medir**, não resultados): uso de CPU em repouso na casa de 1% de um núcleo, memória em ~150–200 MB, GPU próxima de zero; medir em 8 h seguidas, em notebook na bateria, com a faixa visível e coberta.
- Áudio: loops curtos em Ogg, sem 3D.

### 5.6 Compatibilidade e distribuição
- **Windows primeiro.** Mac depois (o Rusty's tem Windows e Mac). Linux/Wayland e transparência são a combinação mais instável; deixar de fora do lançamento. O Rusty's tem tela preta no Linux e interferência do overlay da NVIDIA — **testar overlay da Steam e do driver** cedo.
- Steam: integração via **GodotSteam** (extensão) para conquistas, nuvem e rich presence. Save em `user://` para a Nuvem do Steam.
- Dois ciclos de vida a tratar: o jogo aberto na inicialização do Windows (opção) e o jogo sendo fechado pelo encerramento do sistema sem aviso (salvar a cada poucos minutos + ao receber o pedido de fechamento).

### 5.7 Estrutura de projeto sugerida (para a hora de construir)
```
bunker/
  project.godot
  data/balance.json        # ← todo o balanceamento aqui (culturas, itens, antena, visitas...)
  data/radio_pt.csv        # falas por chave; um CSV por idioma
  scripts/sim/             # lógica pura: economia, tempo, offline, save (sem nós)
  scripts/view/            # cenas e animações que só leem o estado
  scenes/                  # strip.tscn, drawer.tscn, bunker_room.tscn ...
  tools/economia_sim.py    # esta simulação, como oráculo até existir teste no Godot
  tests/                   # simulação headless de N dias que checa os marcos
```
O oráculo Python vira um teste automatizado: `godot --headless` roda 14 dias simulados e confere que a antena 5 cai entre os dias 13 e 16.

### 5.8 Riscos de plataforma (lista curta)

| Risco | Gravidade | Mitigação |
|---|---|---|
| Transparência indisponível/instável em alguma combinação de GPU/driver | alta (se usar transparência) | começar opaco; transparência só como opção |
| "Fora do polígono não desenha" no Windows | média | janela retangular; sem clique atravessando |
| Sem "sempre atrás" nativo | média | janela normal; ou extensão nativa só se for essencial |
| Sem atalho global / sem bandeja no Linux | baixa | botão na faixa; bandeja no Win/Mac |
| Janela fora da tela (bug do Rusty's) | média | validação ao abrir + reset garantido |
| Consumo em segundo plano | **alta** | FPS baixo, modo economia, medir cedo |
| Overlays (Steam/NVIDIA) interferindo | média | testar com e sem overlay |
| Tooltips recortados pela janela pequena | média | gaveta (5.3) |

### 5.9 O teste técnico que resolve a decisão 1
Um projeto Godot vazio com um retângulo que: abre ancorado na área útil, arrasta, recolhe, cresce em largura, anima 8 quadros, roda 8 horas e é medido (CPU/GPU/RAM, desktop e notebook na bateria). Depois, uma segunda versão com transparência + polígono. Critério: se a opaca passa e a transparente dá qualquer problema em duas máquinas, fica opaca. É barato, e faz **antes** de gastar com arte.

---

## 6. Ritmo da narrativa (lente 5)

### 6.1 Duas listas que se contradizem no conceito
O conceito tem **uma sequência de história** (estática → música → homem dos números → "alguém aí? câmbio" → mulher do abrigo, que não é ela → ... → voz dela) e **uma tabela de desbloqueios** (2 = homem das sementes, 3 = caravana, 4 = velho da música das 18h, 5 = mulher do norte). São vozes diferentes em ordens diferentes. Proposta que junta as duas para o **MVP de 5 níveis**:

| Nível | O que ele ouve | O que libera (mecânica) | Emoção | Dia (plano 14 d) |
|---|---|---|---|---|
| 1 | Estática; às vezes um tom, ruído | batata; canteiro, gotejador, moinho, calha | solidão | 0 |
| 2 | **O homem das sementes** (voz prática); música muito longe ao fundo | **feijão**; cisterna | alívio: tem gente | 2,4 |
| 3 | **A caravana** (e, de noite, o homem que lê números) | **visitas ×2**; prateleira, bateria, roldana | rotina; o mundo continua | 6,4 |
| 4 | **O velho da música das 18h**; "...alguém aí? câmbio" ao fim | **tomate + estufa**; painel | calor, nostalgia | 8,5 |
| 5 | **A voz dela**: "Eu tô viva. Tô a caminho. Vai demorar, mas eu vou chegar." | bomba, esteira; modo **preparar a casa** | catarse | 14,5 |

A mulher do abrigo do norte ("não é ela") vira **nível extra entre o 4 e o 5** na versão longa: a duração cresce **inserindo níveis no meio e subindo preços**, mantendo fixos o primeiro e o último marco. Isso responde "10 dias ou 30 dias" sem reescrever a história.

### 6.2 Cadência emocional
Falsa esperança logo antes da voz dela (a mulher do norte) é o clássico e funciona; no MVP de 5 níveis, o "alguém aí? câmbio" no fim do nível 4 faz esse papel (uma voz perdida que **ainda não é ela**). O espaçamento 4 / 2 / 6 dias entre marcos é aceitável, mas os dois "buracos" (dias 2,4–6,4 e 8,5–14,5) pedem conteúdo.

### 6.3 Rádio programada [reusa as ~30 falas; sem sistema novo]
Cada nível entrega, ao subir, **1 fala de chegada** + **2 a 3 falas "de programa"** em horários reais nos dias seguintes (ex.: o velho toca música às 18h; o homem dos números lê às 23h) + **1 reação dele** (ele resmunga, anota). Isso mantém o conteúdo constante entre os marcos e transforma o relógio real em tempero. Tudo cai no Diário (4.4).

### 6.4 Pós-contato: finito, com lista (resposta a "como manter vivo")
O conceito propõe "preparar a casa" com frases sorteadas e "pode durar para sempre". Recomendo **dar-lhe forma sem inventar sistema**:

- A casa dela é uma **lista fechada de ~6 a 8 coisas** (a cama, o canto, a planta de que ela gostava, o cabide do casaco, a segunda caneca, a foto na parede). Já são os itens de decoração que o conceito prevê. [conteúdo: 6–8 objetos]
- Cada coisa que ele monta é **respondida por uma mensagem dela**, em ordem de *viagem* ("passei pelo rio", "tem uma ponte caída", "faltam dois dias") com algumas aleatórias de enchimento. [conteúdo: ~15–20 falas]
- Isso dá à decoração uma **função narrativa** (cada item destrava uma fala), resolvendo o problema de que decoração não rende nada.
- Duração do pós-contato: o que a lista e o relógio impuserem (alvo ~7 dias), **não infinita**.

### 6.5 Ela chega? (pergunta em aberto) → **Sim, na 1.0, fora da tela**
Raciocínio:
- O conceito já descartou "mundo limpo como objetivo final" porque tira o motivo. Mas aqui o motivo é o **reencontro**, e um jogo pago de 14+ dias sem desfecho tende a render a avaliação "não entrega". O risco de decepção do jogador é maior que o risco de "tirar o motivo".
- Ela **nunca aparece na tela** (regra do conceito) e isso se mantém: a escotilha abre, a luz desce pelo duto, ele olha para cima. Corte. Na manhã seguinte há **duas canecas** e o casaco no cabide. [reusa objetos da lista]
- **Epílogo (modo contínuo):** o jogo segue funcionando, com um comportamento novo a custo baixo (ele senta e *não está mais sozinho*: o mesmo assento, o mesmo ritual, com a segunda caneca) e um banco de **bilhetes na mesa** no lugar das mensagens de rádio. O bunker vira uma "tela de descanso" viva, cozy, sem fim.
- Alternativa legítima, mais autoral e mais arriscada: ela **nunca chega**; a última mensagem é "continue, eu estou indo" e o jogo fecha em suspenso. Eu não faria na 1.0.
- Cobertura barata: construir o pós-contato **dirigido por dados** (lista de marcos). A última linha "ela chega" pode ser acrescentada depois sem mexer no resto.

---

## 7. Os primeiros 10 minutos (lente 6)

Objetivo: o jogador entende, **sem ler texto**, o que fazer, que o jogo continua sem ele, e que "tem algo aqui". Roteiro:

| Tempo | O que aparece | O que ele aprende |
|---|---|---|
| 0:00 | A faixa abre. Ele está sentado. A lâmpada acende (luz amarela). O rádio chia baixinho. Dois vasos; um tem broto. Escotilha com caixa vazia. | O mundo está vivo. Quem é ele. |
| 0:20 | Passar o mouse sobre um objeto o **contorna**. Um ícone de semente flutua sobre o vaso vazio. | "Isto é clicável" (contorno é a affordance, não texto) |
| 0:40 | Clique no vaso → escolhe batata (única opção) → "sempre" (2.3). Ele anda, planta. | Uma ordem; o jogo continua sozinho depois |
| ~3:00 | **A primeira colheita é de propósito rápida** (ciclo do tutorial). Ele colhe, carrega, deixa na caixa. | Existe um ciclo e ele termina |
| ~5:00 | Batida na escotilha → a caixa vira um monte de sucata. **Só então aparece o contador de sucata.** | Troca; o que sobra de comida vira dinheiro |
| ~7:00 | Um item da gaveta acende em verde (primeiro objetivo barato). | "Isto é o que se faz com a sucata" |
| ~9:00 | Ele martela; a coisa nasce. O rádio muda o chiado por um instante. | Construir; e que o rádio importa |
| ~10:00 | Fica claro que pode fechar: ele continua. | Idle |

Princípios: **revelação progressiva** (sucata só depois da primeira venda; energia só quando algo a pedir; antena só quando houver sucata para ela); **o mouse com contorno** é o tutorial; um único texto no início é aceitável se for um rádio. O Rusty's é criticado por "sem tutorial" (as avaliações dizem que mecânicas-chave ficam obscuras): a resposta aqui é ícone e consequência, não pop-up.

---

### 7.2 Necessidades e vitais na barra (13/10, versão simples)

Pedido do playtest: "não tem as infos do personagem, a gente não fala que dia é, não tenho info da energia". Implementado: **fome, água e sono** (0..1) com três medidores redondos no cartão do Joaquim (porcentagem, aro cinza/âmbar/vermelho); o retrato na barra ganha moldura da pior necessidade; **"Dia N"** sempre na barra; **raio de energia** "uso/oferta" que fica vermelho e pisca quando falta (o gerador pisca no bunker; o cartão do gerador mostra "Ele pedala: gasta tempo dele" quando é a bicicleta). Comida = estoque de cestos (o mesmo que se vende), água flui sozinha (a bomba precisa de energia), sono volta à noite. Morte só por comida (2 dias no vermelho) ou água (1 dia) **depois do aviso visto**, com tela de fim (dias vividos, Ler o diário, Recomeçar). Diferenças do mock v6/v8: sem máquinas geladeira/filtro/cama ainda; os medidores moram no cartão, não na barra; vermelho de comida/água não para o trabalho (só o piso de 60% que já existia), porque parar travaria a colheita que o tira do vermelho.

### 7.3 Ciclos em minutos (13/10)

Playtest: "não posso esperar 2 horas por uma batata". Rebalanceado em `data/balance.json` (referência: Rusty's, ciclos de 1 a 13 min): **batata 3 min, feijão 8 min, tomate 15 min** (eram 120/150/180); primeira colheita em 2 min (eram 20); cada clique de ajuda adianta 0,4 min (cinco fecham a primeira colheita). O passo da Sim passou de 10 para 1 minuto (um ciclo de 3 min precisa de passos finos; o offline de 72 h leva ~0,6 s) e uma estrutura pode colher mais de uma vez por passo. Tarefas do Joaquim (plantar, regar, carregar) foram divididas por 30 para manter a carga de trabalho, a capacidade da caixa foi multiplicada por 40 (560 / 880 / 1360 / 2000 cestos) e os preços por cesto foram recalculados (batata 0,6, feijão 2,6, tomate 7,0): é a renda por minuto de antes vezes 24. **Custos, antena e metas não mudaram.** Resultado medido pelo bot de 3 check-ins/dia: antena 2 no dia 0,5, antena 3 no 0,8, antena 4 no 1,4, antena 5 no 1,8 (antes 14,5); jogando ativamente (vendendo a cada 10 min) a antena 5 sai em cerca de um dia. A jornada pós-contato continua em 7 dias. Para esticar ou encurtar tudo, o único botão é o preço por cesto (`crops.*.price`), e `test_targets` guarda a janela do teste de ritmo.

### 7.1 Revisão depois do primeiro playtest (início guiado)

O primeiro teste em jogo mostrou o que a seção acima previa e o build não entregava: ao abrir, não ficava claro o que fazer, de onde vem a sucata nem por que o jogo roda sozinho. Mudanças:

- **Introdução** de 4 telas só no primeiro jogo (quem é ele, por que anda sozinho, colheita → cesto → sucata → máquina).
- **Clique é ordem, máquina automatiza**: no começo o jogador manda o homem cuidar dos vasos, levar a caixa ou martelar a obra clicando no alvo; ele larga o que fazia, anda até lá e só então a ajuda vale (fila de até 4, marcas numeradas). Assim a ficção se mantém: não há "mão mágica" agindo enquanto ele martela em outro lugar. (Playtest de 13/10.) O gotejador encerra o pedido nos vasos, a calha encerra o pedido da caixa. A automação chega por volta do primeiro dia, não na antena 3. (Rusty's Retirement não pede cliques; o ritmo dele vem de sempre haver a próxima compra, que é o que o HUD de objetivo copia.)
- **Faixa de status** sempre visível, de uma linha: `[sucata] N sucata | ★ meta` (sugerida por `balance.guide.order`, ou a fixada); juntando, uma barra com "faltam N"; pronta, "✓ Comprar X". O passo do tutorial é uma linha curta ("3/4 Clique na caixa") com seta e contorno piscando no objeto. Explicações só no hover. (Playtest de 13/10: "textos muito grandes", "não entendo o que cada número quer dizer".)
- **Feedback da colheita**: sem barrinha sob o vaso (uma planta leva 120–180 min e a barra não parecia andar); check verde quando pronta, relógio com a contagem no hover, "+1 cesto" ao colher. **Relógio único** para tudo que leva tempo (planta, obra, escavação, espera da caixa): círculo de 9 px que enche no sentido horário + "1h48"/"45min"/"agora"; obra e escavação mostram sempre (uma por vez), o resto no hover.
- **Nada de aba Estado**: o que cada coisa tem a dizer mora nela. Cartões ao clicar: Joaquim (o que faz, "acorda 6h", dia e hora), caixa (cesto + barra, "cabem N", botão "Vender [cesto]4 -> [sucata]4", espera), gerador ("Sobra 1"/"Falta 1!" + quadradinhos + "Geradores") e antena ("Antena N" + custo do próximo nível + jornada da casa depois do contato). Hover em tudo que é clicável: contorno de 1 px e etiqueta curta (cinza + relógio quando não dá para usar agora). O selo de cestos só aparece na caixa quando ela está cheia. O protagonista tem nome: **Joaquim**, com um retratinho no canto da barra de cima que abre o cartão dele (clicar nele na cena também abre).
- **O andar de baixo tem função**: a despensa é o estoque visível (os cestos colhidos aparecem nas prateleiras e, acima da capacidade, no chão) e as salas novas são cavadas para baixo (sala 2 no andar C, sala 3 no andar D), com o poço da escada ligando tudo. O homem usa a escada de verdade: colhe e leva os cestos para a despensa; a ordem da caixa o faz descer, pegar os cestos e subir à escotilha; cavar o faz descer até a escavação. A janela fica fixa em 136 px lógicos (2 andares, é uma barra de tarefas); o bunker tem 136, 187 e 238 px com 1, 2 e 3 salas e a vista rola (roda do mouse, Shift+roda para os lados, ou arrastar), com a câmera seguindo o homem e um mapinha minúsculo. O andar de cima é uma fileira de cômodos (escotilha, horta, oficina, quarto) separados por parede com porta, cada linha de itens só vai no cômodo da sua função.

## 8. Áudio (lente 7)

O rádio é o meio da história **e** o jogo toca em segundo plano, perto de reuniões, vídeos e música do jogador. Princípios:

1. **Silencioso por padrão até a primeira interação**; depois, volume baixo (ambiente em ≈ −24 dB). Botão de alto-falante sempre na faixa.
2. **Três modos:** *Silencioso* (nada; falas viram texto com balão), *Ambiente* (zumbido, goteira, máquinas; o rádio só em texto), *Completo*. Padrão: **Ambiente**.
3. **Texto primeiro, áudio depois.** As falas do rádio são legíveis (balão curto sobre o rádio, ~8–10 s, e depois no Diário). Áudio de fala é opcional e *não* é necessário para entender nada. [reduz escopo: não precisa de dublagem das ~30]
4. **A única fala que vale gravar é a voz dela** (a do nível 5). Uma gravação de uma pessoa, poucos segundos, para o momento que o jogo inteiro espera. [conteúdo: 1 gravação, com legenda]. As demais podem ser texto + ruído/rádio sintetizado (chiado, tons, estática que "abre" quando a voz entra).
5. **Música só existe dentro do mundo** (a que chega pelo rádio: a distante do nível 2, a do velho das 18h). **Sem trilha não-diegética.** Reduz o escopo a 3–5 faixas e reforça o pilar de que o rádio é o centro.
6. **A mixagem conta o progresso:** cada máquina construída acrescenta um loop curto (corrente da bicicleta, vento do moinho, bomba, esteira). Com tudo ligado, o bunker "soa" como uma engenhoca. Um loop por máquina. [conteúdo: ~12 loops curtos, reusa o estado de construção]
7. Barramentos: Master, Rádio, Ambiente, Interface. Ogg, loops de 30–60 s.
8. Se a música vier de IA ou de banco, **conferir licença e a política de IA da Steam** (seção 10.7).

---

## 9. Legibilidade em pixel art minúscula (lente 8)

- **Estado por forma, nunca só por cor** (daltonismo e a paleta limitada de 16–24 cores): planta com 4 estágios de altura diferente (semente, broto, meio, madura); murcha = silhueta caída; máquina ligada = peça se movendo + luz acesa, desligada = parada; energia faltando = lâmpada piscando; caixa cheia = pilha que passa da borda.
- **Uma cor reservada para sinais** (4.5). A paleta fixa permite validar por script que nenhum objeto comum usa essa cor.
- **Ícones de estado de 8×8 px** (comida, energia, rádio, objetivo), sempre no mesmo canto relativo ao objeto.
- **Personagem de 32 px legível pela silhueta da pose**, com o **objeto na mão desenhado à parte** (balde, martelo, lata, livro). Com isso, poucas poses base produzem muitos comportamentos: *em pé/andando*, *agachado*, *carregando*, *martelando*, *deitado*, *sentado*. O conceito diz ~6 animações no MVP: **andar, agachar (plantar/colher/regar), carregar, martelar, dormir, sentado (ler/escutar rádio)**, e as outras atividades de "viver" (escrever, flexão, olhar a foto) entram depois trocando só o objeto. [reusa]
- **Tooltips só na gaveta** (5.3); na faixa, nada de texto.
- **Fonte pixel com cobertura completa de português** (ã, ç, é, õ...) e, se formos localizar para CJK, família com variantes de 12–16 px; checar licença.
- **Acessibilidade:** tamanho de texto ajustável; reduzir piscar (lâmpada) com opção; legenda da voz; sem input temporizado (o jogo já é assim).
- **Lições do conceito sobre PixelLab continuam valendo** (paleta forçada por script, "peça de ouro" primeiro, modelo de prompt fixo, retoque manual, testar 3 a 4 assets antes do lote). Acrescento: avaliar a **peça de ouro já no tamanho real de uso (×2 numa faixa de ~160 px de altura)**, porque inconsistências que somem em zoom grande aparecem na faixa.

---

## 10. Mercado e produção (lente 9)

### 10.1 Comparáveis (pesquisados)

| Jogo | O que é | Dados observados | O que aproveitar / evitar |
|---|---|---|---|
| **Rusty's Retirement** (Mister Morris Games, abr/2024) | Idle de fazenda na faixa da tela | Preço de tabela US$ 6,99 (US$ 4,19 em promoção na consulta). Windows e Mac. 11 idiomas. **Sem demo** na Steam. DLC "Supporter Pack" (~US$ 4), com ~11% de adesão e mais de US$ 111 mil. China = 26% das vendas. Mais de 330 mil unidades (fonte do setor) / ~550 mil até jul/2025 (conceito). Lançou junto do Farming Fest da Steam, com redes sociais e integração com Twitch. | **Aproveitar:** leve e relaxante; acessibilidade já na ficha (volume, texto ajustável); múltiplos saves. **Evitar:** o que as avaliações criticam: conteúdo fino/grind no fim, "não é idle no começo", sem tutorial, uso alto de CPU/GPU em alguns PCs, bug de "sempre por cima", historinha mínima |
| **Desktop Island: Idle Together!** (BiteMe Games, previsto dez/2026) | Vida cozy cooperativa no desktop | 4 modos (tela cheia, rodapé, janela flutuante, só notificações), até 5 jogadores, 16 idiomas | Os modos de exibição já são expectativa de mercado |
| Linha de "janelinha" barata: *My Little Life*, *Idle Waters*, *Not Monday Cafe*, *Maltese's Fluffy Onsen*, *Whimside*, *Mushroom Nook*, *Village Tale*, *Tiny Pasture*... | Idle/colecionável na borda da tela | Preços observados de ~€ 0,5 a € 9, maioria em €2–6 (com descontos fortes de 50–90%) | A categoria é **cheia e barata**: preço alto não se sustenta; diferencial tem que ser claro |
| *TBH: Task Bar Hero* | Idle de barra de tarefas | Relatos **não verificados** de fórum sobre ~200 mil jogadores simultâneos e problemas de bots | Sinal de que a categoria está quente, não um dado |

**O que ninguém na lista parece fazer** (hipótese, verificar com mais busca antes de apostar nisso na loja): um idle de desktop **com narrativa emocional**. As críticas ao Rusty's ("história mínima") apontam espaço, mas é uma aposta, não um fato.

### 10.2 Posicionamento
Gancho em uma linha: **"Um homem, um rádio, uma promessa."** Tags prováveis: Idler, Cozy, Pixel Graphics, Relaxing, Post-apocalyptic, Emotional, Atmospheric, Resource Management, Singleplayer. Cápsula: o homem no corte do bunker com a lâmpada e o rádio, **sem** texto explicando. Windows primeiro.

### 10.3 Preço
Âncora: Rusty's em US$ 6,99 de tabela. Recomendo **US$ 4,99–5,99** na 1.0 (história + ~14 dias de jogo + arte própria) com desconto de lançamento pequeno; preços regionais (BRL, e mercados asiáticos). A "Supporter Pack" sem conteúdo de jogo (trilha, arte) é um experimento barato **depois** de o jogo estar pronto.

### 10.4 Demo e Next Fest
- Um idle em tempo de relógio tem um problema específico: o Next Fest dura poucos dias e ninguém chega à antena 3 numa demo de 14 dias. **A demo precisa de relógio acelerado** (constante em `balance.json`; ex.: tempo ×6 ou preços ×0,25) para que o gancho ("...alguém aí? câmbio") chegue em ~1 a 3 dias de relógio. Também isso dá uma primeira sessão de 10 minutos que **fecha o ciclo** (seção 7).
- **A demo termina na antena 4**, no "alguém aí? câmbio", sem a voz dela (gancho, não spoiler).
- Números de referência (pesquisa do Next Fest de fev/2025, amostra declarada de desenvolvedores; **indicativo**): jogos que entram com **~2 mil wishlists** tendem a ver ganho relevante; quem entra com menos de ~1.000 raramente chega ao topo; ~17% de quem joga a demo põe na lista (melhor caso ~32%); lançar poucas semanas após o Fest "funciona". Conversão de wishlist em venda observada em jogos de outubro/2025 foi de ~1,3% a 3,8% na primeira semana (até 5,5% após ~23 dias no melhor caso). Tratar como faixa grosseira.
- O Rusty's lançou **sem demo** e foi bem; a demo aqui é para *quem não conhece o gênero* e para o gancho da história, não obrigação.

### 10.5 Localização
Texto total estimado: ~100 *strings* (≈30 falas do rádio, 20 de pós-contato, 30 de diário/interface, 20 de conquistas), da ordem de **mil a mil e quinhentas palavras** — pequeno. Ordem: **PT-BR → EN** (obrigatório) → **zh-Hans** (a China foi 26% das vendas do Rusty's), depois ja/ko/es. Mecânica: `TranslationServer` com CSV/PO, chaves estáveis, folga de ~30% no tamanho dos balões (inglês e alemão são maiores) e fonte com CJK. Orçar tradução profissional (o volume é baixo).

### 10.6 Riscos e o teste mais barato de cada um

| # | Aposta arriscada | Teste mais barato | Sinal de passou |
|---|---|---|---|
| 1 | **A janela viável e leve** em PCs reais | Teste técnico (5.9): retângulo animado, 8 h, desktop e notebook | CPU ≈ 1%, janela não some, DPI/monitores ok |
| 2 | **O ritmo e a vontade de olhar** | Simulação (feita) + um *greybox* no Godot, com retângulos, relógio ×20 para ajustar, depois 3 dias no ritmo real no seu próprio PC | Você abre a gaveta por vontade ≥ 2×/dia; não sente falta de ação |
| 3 | **A história segura 14 dias com 25 falas** | **Teste sem código**: mandar 2–3 falas por dia, nos horários da programação, a 3–5 pessoas durante 5 dias (mensagem de texto), e perguntar "o que acha que vai acontecer?" e "quer a próxima?" | Pedem a próxima; palpitam sobre a esposa |
| 4 | **Arte de IA consistente e aceita** | Peça de ouro + 3–4 objetos pela paleta forçada, vistos em ×2; mostrar a comunidade pixel-art/cozy sem aviso prévio e ler a reação | Consistência visível; reação não hostil |
| 5 | **Demanda no gênero saturado** | Página da Steam cedo com um GIF de 15 s e a frase-gancho; acompanhar lista de desejos | Ritmo de lista de desejos crescente sem anúncio pago |
| 6 | **Offline e relógio real não irritam** | No greybox, deixar fechado por um fim de semana e ler o Diário | O Diário parece "uma boa volta", não um relatório |
| 7 | **Preço/duração** | Plano de preços ×0,7 vs ×1,6 em duas pessoas | Ninguém abandona por falta de coisa nova |

### 10.7 Riscos de produção que o conceito não lista
- **Declaração de IA na Steam:** a Steam pede que o desenvolvedor declare uso de IA generativa em conteúdo pré-gerado; arte do PixelLab entra aí. Além da regra, parte do público cozy/pixel-art é sensível a isso. **Conferir o texto vigente da política antes de publicar** (não verifiquei a versão atual). Retoque manual e eventual artista (já no plano B) reduzem o risco.
- **Taxa de publicação na Steam** (hoje em torno de US$ 100 por jogo, recuperável após um limite de receita — conferir) e as datas de Next Fest: planejar a página com meses de antecedência.
- **Testes de QA multi-tela** (DPI, 2+ monitores, barra de tarefas automática) não cabem nas estimativas do conceito; contam como trabalho.
- **O conceito estima "~2 meses" noites e fins de semana.** Eu acrescentaria ao cronograma, sem prometer prazo: teste técnico (antes de tudo), áudio, localização, página da Steam/marketing e QA de plataforma. Nenhum deles é grande, mas todos somam.

### 10.8 O protótipo HTML do conceito (recomendação)
**Não faria.** Motivos: (1) a simulação já responde "os números fazem sentido" sem interface; (2) o que o autor quer *sentir* ("deixar rodando e ver se tem graça") só se testa **na faixa, no desktop, durante dias**, e uma página no navegador não tem nem a janela, nem o consumo, nem o relógio de verdade; (3) código HTML seria descartado ao ir para o Godot. O equivalente certo é um *greybox* no Godot com retângulos coloridos, que também valida a janela. Se o autor quiser um brinquedo imediato para "sentir" o loop, o HTML ainda é a opção mais rápida de escrever — mas aí é só curiosidade, não etapa do plano.

---

## 11. Perguntas em aberto do conceito → recomendação

| Pergunta | Recomendação |
|---|---|
| Faixa embaixo da tela ou janela no canto? | **Janela-faixa opaca ancorada no rodapé, que cresce quando ele escava** (5.2); decidir de vez após o teste técnico |
| Qual engine, e quanto o autor programa? | Godot (já decidido). Manter **dados fora do código** (`balance.json`), lógica pura separada da cena e teste automatizado de simulação (5.7) |
| Nome | Critérios: curto, pesquisável na Steam, funciona em inglês, não entrega o final. Ideias para testar: **"Câmbio"** (termo de rádio, aparece na fala "...alguém aí? Câmbio"), **"Escotilha"**, **"Sinal"** (genérico demais?). *Quantos Dias?* conta o tempo em vez da espera; ok como provisório. Verificar disponibilidade na Steam antes de investir |
| A esposa chega? | **Sim, na 1.0, fora da tela**, depois de uma jornada finita de "preparar a casa"; epílogo contínuo (6.5) |
| Cachorro | Continua fora. Se um dia entrar, **sem sprite**: presença só por som na escotilha (arranhão, latido), custo quase nulo e sem animar um segundo personagem |

### 11.1 Buracos e inconsistências que o conceito deixa implícitos
Cada linha é uma decisão pequena a registrar antes de construir.

| # | Buraco | Proposta |
|---|---|---|
| 1 | "Plantar" é ordem repetida ou configuração? | Configuração por vaso (2.3) |
| 2 | Água: recurso ou serviço? | Serviço com capacidade, sem estoque (3.6) |
| 3 | Sequência de história vs tabela de desbloqueios | Tabela unificada (6.1) |
| 4 | O que "automatizar" significa? | Cada linha de serviço tira uma tarefa dele (3.3) |
| 5 | Dia de jogo = dia real? | Sim (4.1) |
| 6 | O que acontece com o jogo fechado? | Simula o tempo corrido, mesmo código, teto 72 h (4.2) |
| 7 | Dá para desmontar e mover? | Mover grátis; desmontar devolve 100% (3.6) |
| 8 | A fome | Piso de 60% de velocidade; sem espiral (3.3) |
| 9 | Bomba e esteira: antes ou depois do contato? | Depois (são compras de "casa", pós-antena 5) |
| 10 | Quantos níveis de antena no jogo completo? | MVP = arco completo em 5; versão longa insere níveis no meio (6.1) |
| 11 | A decoração não rende nada | Cada item do pós-contato destrava uma fala dela (6.4) |
| 12 | Onde fica a interface numa janela de 160 px? | Gaveta (5.3) |

---

## 12. Ideias novas, avaliadas

Só o que acrescenta valor com custo baixo. Em ordem de recomendação.

| Ideia | Tipo | Recomendo | Observação |
|---|---|---|---|
| Ordem permanente por vaso | reusa | **MVP** | fecha o buraco 2.3 |
| Diário do rádio | UI + conteúdo pequeno | **MVP** | resolve offline, noite, legendas e releitura |
| Rádio programada por horário real | reusa as falas | **MVP** | preenche os buracos de ritmo |
| Gaveta de gestão | UI | **MVP** | resolve a falta de espaço na faixa |
| Mover/desmontar sem perda | regra | **MVP** | zero arrependimento |
| Quadro de avisos com 1 objetivo fixado + balão dele | sistema pequeno | MVP se sobrar | sinal de atenção diegético |
| Voz real dela (1 gravação) | conteúdo | **1.0** | o momento mais caro de emoção do jogo |
| Jornada finita no pós-contato + epílogo | conteúdo | **1.0** | desfecho |
| Conquistas (~12, só com conteúdo que já existe: "primeira colheita", "terceiro cômodo", "ouviu todas as vozes", "7 noites seguidas") | conteúdo | 1.0 | visibilidade na Steam, custo baixo |
| Clima (chuva enche a cisterna, frio aumenta o consumo de energia) | sistema pequeno | pós-1.0, talvez | dá variedade à cauda longa, sem personagem novo; não entra se estourar escopo |
| 4º cômodo opcional pós-contato ("quarto dela") | conteúdo | 1.0 | espaço para a decoração final |

Considerei e **não** recomendo: sistema de humor (cria uma camada nova que ninguém pediu), toggles liga/desliga de máquinas (microgerência), eventos aleatórios negativos (quebra o anti-pilar de não punir), prestígio/novo jogo+ (o desfecho é o objetivo).

### 12.1 Para o futuro: o bunker como companhia no mundo real (ideia do autor, fora do escopo atual)

Ideia: a música que toca no rádio dele também toca para o jogador (por exemplo, enquanto estuda), e talvez ligar isso ao que a pessoa já ouve (YouTube etc.).

**Cuidado com a fronteira da lista de descartadas.** "Jogo espelhando a vida real (estuda quando você estuda, timer de foco, passos e sono)" foi descartado porque virava app de produtividade. A linha que separa os dois casos: **o jogo dá algo ao jogador** (música, companhia) **vs. o jogo mede o jogador** (tempo de estudo, foco). Música e companhia ficam do lado seguro; qualquer contador, meta ou recompensa por estudar, não.

Um argumento a favor, e que cabe no tom: ver alguém trabalhando quieto ao lado enquanto você trabalha é um hábito conhecido (parceiro de foco, vídeos de "estude comigo"). O homem plantando, martelando e lendo já é isso, sem rastrear nada.

| Opção | O que é | Custo / risco | Recomendo |
|---|---|---|---|
| **A. Estação do bunker** | O rádio toca faixas próprias, com filtro de chiado, em modo contínuo ("modo ambiente/estudo"), sem timer e sem texto | [conteúdo] poucas faixas próprias ou licenciadas (a música diegética que o doc já prevê: nível 2 e a das 18h). Sem integração nenhuma | **Primeiro passo, e já combina com a seção 8** |
| **B. Pasta do jogador** | O jogador aponta uma pasta de músicas dele e o rádio "sintoniza" esses arquivos com o mesmo filtro | [sistema pequeno] o Godot carrega MP3/Ogg/WAV de disco (não verifiquei os detalhes de formato); sem questão de direitos, são arquivos dele. Precisa de seletor de pasta, lista e volume com "duck" | Boa segunda etapa, se o A agradar |
| **C. Reagir ao que já toca no PC** | Ele "ouve" a mesma música que você (bate o pé, o rádio acompanha), lendo o que o sistema diz estar tocando | Exige API do sistema (no Windows, o controle de mídia) via código nativo: não encontrei isso nos docs do Godot que consultei. Fica na fronteira "medir o jogador" | Só pesquisar depois; não prometer |
| **D. YouTube / Spotify** | Tocar áudio do YouTube dentro do jogo | Pelos termos de uso do YouTube, até onde sei, não é permitido separar o áudio do vídeo e o player precisa aparecer; o Godot também não traz navegador embutido. **Conferir os termos atuais antes de decidir.** O Spotify permite controlar o app do usuário por API, mas (até onde sei) só com Premium e sem passar o áudio pelo jogo | **Não** apostar nisso agora |

Outros cuidados quando isso entrar: o jogador pode estar ouvindo outra coisa (começar silencioso e baixar o volume automaticamente quando houver outro som); o áudio contínuo custa pouca CPU, mas precisa respeitar o modo economia; faixa de terceiros precisa de licença clara (e de declaração de IA na Steam, se for gerada).

Se um dia for adiante, o ganho de mercado pode ser real: "estude comigo" e lo-fi têm público grande e parecido com o de jogo cozy de desktop. Mas só vale depois de o jogo provar que a faixa na tela funciona (seção 5.9).

---

## 13. O que validar no playtest (por ordem)

1. **A janela:** abre, arrasta, some, volta; roda 8 h sem esquentar; funciona em 2 monitores e em notebook na bateria.
2. **O olhar:** você olha para a faixa sem ser chamado? Quantas vezes por dia abre a gaveta?
3. **As moedas das compras:** o que você *sentiu* ao comprar gotejador, moinho, cisterna? Percebeu a mudança?
4. **O gargalo legível:** você consegue dizer, olhando, por que a renda parou? (caixa cheia, ele ocupado, vasos vazios)
5. **O ritmo narrativo:** os dois buracos (4 e 6 dias) pesam? A programação do rádio ajuda?
6. **O offline:** o Diário "a volta" parece bom?
7. **A voz dela:** o momento paga a espera?
8. **A preferência do desfecho:** ela chegar fora da tela decepciona ou emociona?

---

## 14. Próximos passos sugeridos (sem datas)

1. **Decidir** os 5 itens da seção 0 (todos cabem numa conversa).
2. **Teste técnico da janela** (5.9). Gate: se falhar, muda o formato antes de qualquer arte.
3. **Greybox no Godot** com `balance.json` vindo desta tabela e o relógio acelerável; deixar rodando alguns dias (riscos 2 e 6).
4. **Teste de texto sem código** (risco 3) em paralelo, enquanto o greybox sai.
5. **Peça de ouro** e 3–4 objetos, vistos no tamanho real (risco 4).
6. Só então escrever as ~30 falas finais, a lista final de construções com custos e começar arte em lote.

---

## 15. Arquivos e fontes

**Arquivos**
- `Bunker - Análise de Design.md` — este documento.
- `Ferramentas/economia_sim.py` — simulação (parâmetros no topo; `python economia_sim.py` roda tudo; `--escala 1.6` muda a duração).
- `Ferramentas/saida_economia_sim.txt` — saída da última execução, com a tabela de compras e o retorno de cada uma.

**O que a simulação NÃO faz** (para não ler mais do que ela diz): não modela slots de espaço nem a distância real; tempos de tarefa são constantes (no jogo saem do layout); sono é fixo (06–22h); compra sempre o primeiro item liberado do plano; vendas por visita são uma média; culturas e preços são chutes iniciais. Serve para estrutura e ordem de grandeza.

**Fontes consultadas**
- Documentação do Godot: [DisplayServer](https://docs.godotengine.org/en/stable/classes/class_displayserver.html), [Window](https://docs.godotengine.org/en/stable/classes/class_window.html), [OS](https://docs.godotengine.org/en/stable/classes/class_os.html), [Engine](https://docs.godotengine.org/en/stable/classes/class_engine.html), [ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html), [StatusIndicator](https://docs.godotengine.org/en/stable/classes/class_statusindicator.html).
- Fórum do Godot sobre janela transparente e clique atravessando: [How can I click through the screen while keeping a transparent screen?](https://forum.godotengine.org/t/how-can-i-click-through-the-screen-while-keeping-a-transparent-screen/64195).
- Rusty's Retirement: [página/dados da Steam](https://store.steampowered.com/app/2666510), [resumo de avaliações (Vaporlens)](https://vaporlens.app/app/2666510/rustys_retirement), [bug de "sempre por cima" (fórum Steam)](https://steamcommunity.com/app/2666510/discussions/0/6761669877509850350), [análise de lançamento e vendas](https://gameindustrylibrary.com/documents/how-rusty-s-retirement-idle-farmed-its-way-to-300k-steam-sales/insights).
- Comparáveis: [Desktop Island: Idle Together!](https://www.gamedeveloper.com/press-release/a-desktop-idler-you-can-play-with-friends-desktop-island-idle-together-announced-for-steam), [jogos similares ao Rusty's (WASDLand)](https://www.wasdland.com/game/rustys-retirement-2666510/similar-games/), [TBH: Task Bar Hero (discussão)](https://steamcommunity.com/app/3678970/discussions/0/571540300205404629/).
- Next Fest: [benchmarks de lista de desejos (How To Market A Game)](https://howtomarketagame.com/2025/03/26/archive-january-2026-benchmarks-how-many-wishlists-can-i-get-from-steam-next-fest/), [conversão de wishlist em compra (Alinea Analytics)](https://alineaanalytics.substack.com/p/wishlist-to-buyer-conversions-for).
