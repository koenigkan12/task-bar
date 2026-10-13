# Fonte do jogo: Jersey 15

- **Fonte:** Jersey 15 (`Jersey15-Regular.ttf`), família "Jersey" (pixel, grade de 15 px).
- **Autoria:** The Soft Type Project (Sarah Cadigan-Fried), https://github.com/scfried/soft-type-jersey
- **Licença:** SIL Open Font License 1.1 (arquivo `OFL.txt`, copiado do repositório google/fonts). Uso comercial e embutir no jogo permitidos; não vender a fonte sozinha; não renomear sem tirar o nome reservado.
- **Origem do arquivo:** https://raw.githubusercontent.com/google/fonts/main/ofl/jersey15/Jersey15-Regular.ttf (licença: .../ofl/jersey15/OFL.txt)
- **Cobertura:** latim com acentos de PT-BR (ç ã õ é ê ó í ú à â ô ü), travessão, dígitos. Sem CJK (para zh/ja/ko será preciso uma fonte de fallback).
- **Importação (Godot 4.6):** `Jersey15-Regular.ttf.import` já está ajustado: `antialiasing=0` (nenhum), `hinting=0` (nenhum), `subpixel_positioning=0` (desligado), `force_autohinter=false`, `oversampling=1.0`. Não mude: com suavização/hinting o texto vira borrão.
- **Candidatas testadas e descartadas:** Pixelify Sans (espaçamento irregular, traço fino), Silkscreen e Press Start 2P (só caixa alta/largas demais para a faixa), VT323 e Jersey 10 (x-height pequeno, "ã" pouco legível a 10 px). Tiny5 e Departure Mono não foram baixadas (Tiny5 não estava no caminho esperado do repositório e não houve tempo de buscar).
