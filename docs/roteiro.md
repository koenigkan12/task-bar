# Roteiro — para revisão do dono

32 falas de rádio, 10 de viagem, 6 de casa, 1 chegada, 29 bilhetes. Tudo em `data/radio.json`, `data/journey.json` e `data/i18n/strings_story.csv` (PT-BR + EN). Rode `python3 tools/content/validate_content.py` depois de editar.

Regras que segui: frases curtas e concretas (cheiro, comida, objeto); nenhum nome próprio; ninguém explica o apocalipse; ele quase não fala (só 1 frase por nível, depois da chegada da voz); ela só existe em voz/texto; nada confirma onde ela estava nem o que houve lá fora. Falas sem fala de verdade (chiado, música) aparecem como legenda entre parênteses.

## Arco emocional por nível
| Nível | Voz que chega | Emoção | O que o jogador sente |
|---|---|---|---|
| 1 | Chiado (`ruido`) | solidão, hábito | "Hoje também não." Ele já esperou antes de você chegar |
| 2 | O homem das sementes + valsa distante | alívio | Tem gente. Alguém ensina feijão |
| 3 | A caravana + números à noite | rotina, o mundo continua | Há comércio, gente cansada e um locutor que erra um número |
| 4 | O velho das seis + voz do norte | calor, depois falsa esperança | A música dá companhia; "alguém aí? câmbio" não é ela (gancho da demo) |
| 5 | Ela | catarse | 3 frases do conceito, intactas. A reação dele: "Tô aqui. Pode vir devagar." |
| Pós-contato | Ela, só por viagem e casa | espera boa | Cada item da casa é respondido; ela avança um trecho por dia |
| Epílogo | Bilhetes na mesa | cotidiano | Agradecimentos, lista de compras, uma planta que cresce; fecha sem fechar |

## Horários do rádio (relógio do jogo)
| Voz | Hora | Observação |
|---|---|---|
| Sementes (`sementes`) | 07h, 17h30 | fazendeiro: manhã e fim de tarde |
| Caravana (`caravana`) | 12h | "passamos todo dia ao meio-dia" |
| O Velho (`velho`) | 18h | música (`music_18h`) |
| Números (`numeros`) | 23h | madrugada é a "janela boa" do rádio; vai ao Diário |
| Norte (`norte`) | 20h30–22h | só no nível 4; sempre à noite |
| Chiado/valsa (`ruido`) | 03h30–22h | restos de sinal; valsa às 21h30–22h |
`day_offset` conta a partir do dia em que a antena chegou ao nível (nível 1: desde o início). Linhas com `day_offset 0` e hora tardia podem já ter passado; o Sim decide se entrega ou pula.

## O que cada voz representa
- **Chiado**: o mundo que ele ainda não alcança; a paciência dele.
- **Sementes**: o conhecimento que se passa de mão em mão; praticidade, joelho que reclama.
- **Caravana**: trocas, estrada, gente em movimento (e a estrada pela qual ela virá: cruzamento, rio, usina).
- **Números**: alguém tão sozinho quanto ele, mas que mantém o ofício. Erra um número no nível 3 e, no 5, diz só "boa noite".
- **O Velho**: o que se faz para a mão não esquecer. A música aguenta um erro.
- **Norte**: a falsa esperança. Também espera por alguém; não explica por quem.
- **Ela**: sempre curta, concreta, bem-humorada com ternura. Fala em "tô", "pra".
- **Ele**: seco e humano; anota.

## Pontes entre vozes (para o jogador atento)
O posto da estrada velha (sementes) e a caravana aparecem na viagem dela (dias 2 e 5); ela ouve o violão do velho às seis (dia 7); o velho errar a segunda parte volta num bilhete.

## Casa e chegada
Falas de `on_item` (cama, cantinho, planta, cabide, segunda caneca, foto) respondem ao que ele montou. A viagem tem 10 falas (dia 1 a 10); com o mínimo de 7 dias, só as 7 primeiras saem, por isso nenhuma diz "faltam X dias": a última diz que está "a uma tarde", descansando, "termina de arrumar, sem pressa", o que funciona em qualquer atraso. Chegada: "Ei. Sou eu. Demorou, mas eu cheguei." Cena: `ending.knock` (três batidas), `ending.light`, depois a tela com `ending.title`/`ending.line.*`; no dia seguinte, `ending.nextday.*` (duas canecas, casaco no cabide).

## Bilhetes (29)
Ordem importa se o Sim os entregar em sequência: 1–6 primeiros dias (sono, cama, café ruim, as cartas dele na gaveta, "um bilhete por dia"); 7–17 casa (lista, desenho, planta, camisa remendada, pilhas, sopa, escada, o sal, gerador); 18–25 rotina (chuva pelo duto, rádio baixinho, tomate, "quantos dias? hoje"); 26–29 calma (lista de novo, "se um dia a gente subir", bilhete vazio, boa noite).

## Chaves de Diário (UI/Sim)
`diary.away.summary` aceita `{hours}`, `{visits}`, `{scrap}`, `{nights}` (plural). Variantes de plural simples: `.v1` (1 visita), `.n1` (1 noite), `.n0` (nenhuma noite), `.v1n1`, `.v1n0`. `diary.away.line` e `.night` aceitam `{hour}` e `{speaker}` (nome de `speaker.*`). `diary.unread.one/.other`.
