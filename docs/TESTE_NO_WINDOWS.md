# Teste manual no Windows

Roteiro para conferir o build exportado (`build/QuantosDias-windows-x64.zip`) numa máquina Windows de verdade. O que dá para testar no Linux já roda em `tests/run_all.sh` e na validação do `tools/build/export_windows.sh`; este roteiro cobre o que só aparece com a janela nativa do Windows.

Anote para cada item: ✅ ok, ❌ falhou (com print e o que fez antes) ou ➖ não deu para testar. Diga a versão do Windows, a resolução e a escala (100%, 125%, 150%...) de cada monitor.

## 0. Preparação
- [ ] Extraia o zip numa pasta sem acento (ex.: `C:\Jogos\QuantosDias`) e numa com acento e espaço (ex.: `C:\Users\Você\Área de Trabalho\Quantos Dias`). Os dois rodam.
- [ ] Para começar do zero, apague `%APPDATA%\QuantosDias\` antes do teste.
- [ ] Propriedades do `QuantosDias.exe` → Detalhes: nome do produto "Quantos Dias?", versão 0.1.0.0. O ícone (rádio aceso) aparece no Explorer, na barra de tarefas e no Alt+Tab.
- [ ] O SmartScreen avisa (exe sem assinatura): *Mais informações → Executar assim mesmo* abre o jogo.
- [ ] Nenhuma janela de console preta abre junto.

## 1. Grudado no rodapé
- [ ] Na primeira abertura a janela aparece no canto inferior esquerdo do monitor principal, **logo acima da barra de tarefas**, sem cobri-la e sem borda.
- [ ] Barra de tarefas em outra posição (direita/esquerda/topo, ou com "ocultar automaticamente"): a janela continua na área útil, encostada embaixo.
- [ ] A janela abre a gaveta (check-in) **para cima**, e a borda de baixo não sai do lugar. Ao fechar a gaveta, volta ao tamanho de antes.
- [ ] Quando ele escava um cômodo, a janela **não muda de tamanho** (continua 2 andares); a cena rola para baixo junto com ele.
- [ ] Roda do mouse sobre a faixa rola a cena; arrastar o chão vazio também; uns segundos depois ela volta a seguir o Joaquim. O indicador de andares (abaixo da alça) aparece só depois da 1ª sala nova.
- [ ] Arrastar pela alça move a janela; soltar perto da borda de baixo não deixa parte dela debaixo da barra de tarefas nem fora da tela.

## 2. Vários monitores
- [ ] Arraste a janela para o segundo monitor, feche o jogo e reabra: ela volta no segundo monitor, no mesmo lugar.
- [ ] Com o jogo fechado, desligue/desconecte o segundo monitor e abra: a janela aparece no monitor principal, visível (não fica fora de todas as telas).
- [ ] Monitores com alturas diferentes e um deles acima/abaixo do outro: a janela não fica cortada em nenhum.
- [ ] Mude qual monitor é o principal (Configurações → Tela) com o jogo aberto: a janela continua visível.

## 3. DPI e escala
- [ ] Escala do Windows em 100%, 125%, 150% e 200% (reabra o jogo em cada uma): a pixel art fica nítida (pixels quadrados, sem borrão) e a janela tem tamanho coerente.
- [ ] Opções → Escala "auto" e 1, 2, 3, 4: o tamanho muda na hora, a borda de baixo fica no lugar e a janela não passa da largura do monitor.
- [ ] Dois monitores com escalas diferentes (ex.: notebook 150% + monitor 100%): arraste de um para o outro. A janela ajusta e não fica gigante nem minúscula.
- [ ] Resolução baixa (1366×768) e alta (2560×1440 ou 4K).

## 4. Bandeja
- [ ] O ícone aparece na bandeja (perto do relógio; pode estar escondido na setinha "^").
- [ ] O menu tem Mostrar/Recolher, Resetar posição, Sempre por cima e Sair, no idioma do jogo.
- [ ] **Resetar posição** devolve a janela ao rodapé do monitor principal, mesmo que ela esteja em outro monitor.
- [ ] **Sair** fecha o jogo e o ícone some da bandeja (passe o mouse sobre a bandeja para ela atualizar).
- [ ] Fechar pelo Gerenciador de Tarefas não deixa ícone fantasma depois de passar o mouse.
- [ ] `QuantosDias.exe --reset-window` (por um atalho ou pelo cmd) abre a janela no rodapé do monitor principal.

## 5. Recolher
- [ ] O botão de esconder na alça transforma a janela numa aba pequena colada na borda de baixo, no canto onde ela estava.
- [ ] Clique na aba: a janela volta ao tamanho e posição de antes.
- [ ] Recolher pelo menu da bandeja faz o mesmo.
- [ ] Recolhida, a simulação continua: espere alguns minutos e restaure; o relógio do jogo andou e houve produção.
- [ ] Com algo novo no rádio, a aba mostra no máximo uma luz verde pulsando, e nenhum som.
- [ ] Feche o jogo recolhido e reabra: abre recolhido (o estado é salvo).
- [ ] Gerenciador de Tarefas: recolhido, o uso de CPU/GPU cai para perto de zero.

## 6. Sempre por cima
- [ ] Desligado (padrão): abrir outra janela por cima esconde o jogo normalmente.
- [ ] Ligado (bandeja ou opções): o jogo fica por cima de outras janelas, inclusive depois de clicar em outro programa.
- [ ] Ligado, com um vídeo em tela cheia (YouTube F11, VLC) e com um jogo em tela cheia: anote o que acontece (aceitável: o jogo some por trás da tela cheia; inaceitável: piscar ou roubar o foco).
- [ ] Ligado, a janela não "foge" para fora dos monitores (problema relatado em jogos parecidos). Se fugir, Resetar posição pela bandeja resolve.
- [ ] A opção fica salva ao fechar e reabrir.

## 7. Offline: fechar e reabrir
- [ ] Jogue uns minutos, anote sucata, cestos e o dia do jogo, e feche pela bandeja → Sair.
- [ ] Reabra logo em seguida: os números batem com o que estava (nada perdido).
- [ ] Feche, espere 30 minutos ou mais e reabra: aparece o "bem-vindo de volta" com o que aconteceu, e os números cresceram de acordo.
- [ ] Feche, adiante o relógio do Windows algumas horas (ou deixe a noite toda) e reabra: o progresso offline aparece e o jogo não trava nem demora para abrir.
- [ ] Volte o relógio para trás e abra: nada de valor negativo, nem perda de progresso.
- [ ] Desligue o PC com o jogo aberto (sem fechar) e religue: o save não corrompe; no máximo perde os últimos segundos.
- [ ] Sem internet (Wi-Fi desligado): o jogo abre e funciona igual.

## 8. Som
- [ ] Ao abrir, nenhum som até o primeiro clique na janela.
- [ ] Depois do clique, no modo ambiente: ambiente e efeitos baixos; o rádio só em texto.
- [ ] Trocar de dispositivo de saída (fone ↔ caixa) com o jogo aberto não trava.

## 9. Consumo (deixe rodando)
- [ ] Gerenciador de Tarefas com a janela parada, sem mouse em cima: CPU baixa (menos de 2% num PC comum) e GPU perto de zero.
- [ ] Notebook na bateria por 1 hora com o jogo aberto: anote quanto a bateria caiu com e sem o jogo.
- [ ] Deixe aberto por 8 horas (um expediente): o uso de memória não fica crescendo e o jogo continua respondendo.

## Ao terminar
Mande a lista com ✅/❌/➖, os prints dos ❌ e, se houve erro, o arquivo `%APPDATA%\QuantosDias\logs\godot.log` (se existir).
