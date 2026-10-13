# Fonte do jogo: Pixelify Sans

- **Fonte:** Pixelify Sans (`PixelifySans.ttf`, variável; vale o peso Regular 400), de Stefie Justprince.
- **Licença:** SIL Open Font License 1.1 (`PixelifySans-OFL.txt`). Uso comercial e embutir no jogo permitidos; não vender a fonte sozinha; não renomear sem tirar o nome reservado.
- **Origem do arquivo:** google/fonts (ofl/pixelifysans). Escolhida pelo Vinícius em 13/10 (comparação em `ui-clareza/7_fontes.png`).
- **Tamanhos:** texto 10 px, título 11 px (`UiTheme.SIZE_*`). Nunca fracionar nem usar `Control.scale` em Label.
- **Importação (Godot 4.6):** `PixelifySans.ttf.import` está com `antialiasing=0`, `hinting=0`, `subpixel_positioning=0`, `oversampling=1.0`. Não mude: com suavização o texto vira borrão.
- **Atenção:** o "a" é de um andar só e fica parecido com "o" em tamanho pequeno. Foi escolha consciente.
- **Cobertura:** latim com acentos de PT-BR. Sem CJK (para zh/ja/ko será preciso uma fonte de fallback). Sem ★ ✓ →: use os ícones do `manifest_ui`.
