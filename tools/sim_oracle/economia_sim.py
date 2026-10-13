#!/usr/bin/env python3
"""Simulador de economia do Bunker (rascunho de design, não é código do jogo).

Modelo fluido em passos de 10 min. Serve para responder, ANTES de abrir a engine:
  - quantos dias de relógio leva chegar à antena nível 5?
  - o jogo é "idle de verdade" (quem olha 1x por dia perde pouco)?
  - quanto vale o progresso offline?
  - alguma compra é dominante, armadilha ou beco sem saída?

Os números ficam todos em CFG/ITENS no topo (mesma ideia do `CFG` do game.js do Four Wardens).
Uso:  python economia_sim.py            -> relatório completo
      python economia_sim.py --escala 1.9   -> multiplica todos os preços
Premissas do modelo (simplificações assumidas, não medidas):
  * "sucata" é a única moeda; comida vira "cestos" (1 colheita = 1 cesto) vendidos na escotilha.
  * receita/dia = min(produção, visitas x capacidade da escotilha) x preço do cesto.
  * o homem tem 16 h acordado/dia; tudo que ele faz (plantar, regar, carregar, pedalar,
    construir) consome esse orçamento. Se faltar tempo, a produção cai proporcionalmente.
  * o jogador faz "check-ins" em horários fixos e compra o que a política mandar.
"""
import argparse
import sys

DT = 10                    # minutos por passo
ACORDADO = (6 * 60, 22 * 60)  # 06:00 - 22:00
CFG = {
    "visitas_por_dia": {1: 3, 2: 3, 3: 5, 4: 5, 5: 6},   # a caravana (nível 3) dobra a frequência
    "capacidade_escotilha": {"balde": 14, "calha": 22, "roldana": 34, "esteira": 50},  # cestos por visita
    "tarefa_plantar_colher_min": 3.0,     # por ciclo por vaso
    "tarefa_regar_min": 5.0,              # por ciclo por vaso, se não houver irrigação automática
    "tarefa_carregar_min": {"balde": 6.0, "calha": 3.0, "roldana": 1.2, "esteira": 0.2},
    "pedalar_fracao": 0.25,               # fração do tempo acordado gasta pedalando a bicicleta
    "rega_automatica": {"lata": 0, "gotejador": 4, "cisterna": 10, "bomba": 99},
    "oferta_energia": {"bicicleta": 3, "moinho": 5, "bateria": 8, "painel": 12},
    "demanda_radio": {1: 1, 2: 1, 3: 2, 4: 2, 5: 3},
    "comer_por_dia": 3,
}
CULTURAS = {  # ciclo (min), preço por cesto em sucata
    "batata": (120, 1.0),
    "feijao": (150, 2.0),
    "tomate": (180, 3.5),
}
# nome: (custo base, antena minima, comodos minimos, energia que consome ao ligar)
ITENS = {
    "vaso":      (8,   1, 1, 0),
    "canteiro":  (40,  1, 1, 0),
    "gotejador": (55,  1, 1, 0),
    "moinho":    (70,  1, 1, 0),
    "calha":     (60,  1, 1, 0),
    "comodo2":   (120, 1, 1, 0),
    "cisterna":  (210, 2, 2, 0),
    "prateleira": (160, 3, 2, 0),
    "bateria":   (190, 3, 2, 0),
    "roldana":   (170, 3, 2, 0),
    "comodo3":   (300, 3, 2, 0),
    "estufa":    (380, 4, 2, 2),
    "painel":    (460, 4, 3, 0),
    "bomba":     (520, 5, 3, 2),
    "esteira":   (430, 5, 3, 2),
}
ANTENA = {2: 70, 3: 160, 4: 340, 5: 640}      # custo de subir PARA o nível
ANTENA_REQ = {2: (1, 1), 3: (5, 2), 4: (8, 2), 5: (12, 3)}   # (energia minima, comodos)
PLOTS = {"vaso": 1, "canteiro": 3, "prateleira": 5, "estufa": 6}
MAXQ = {"vaso": 4, "canteiro": 2, "prateleira": 1, "estufa": 1}

POLITICAS = {
    # Ordem do plano do jogador. Regra: compra o primeiro item da lista que está liberado;
    # se não tem sucata ainda, ESPERA (um jogador com plano junta para a antena, não desvia).
    "equilibrada": ["vaso", "vaso", "antena", "moinho", "canteiro", "calha", "canteiro", "gotejador", "comodo2",
                    "prateleira", "bateria", "cisterna", "antena", "estufa", "roldana", "comodo3", "painel",
                    "bomba", "esteira"],
    "economia_primeiro": ["vaso", "vaso", "vaso", "vaso", "gotejador", "canteiro", "moinho", "canteiro", "calha",
                          "comodo2", "cisterna", "bateria", "roldana", "comodo3", "prateleira", "estufa",
                          "painel", "bomba", "esteira", "antena", "antena", "antena", "antena"],
    "antena_primeiro": ["antena", "moinho", "antena", "comodo2", "bateria", "comodo3", "antena", "antena",
                        "vaso", "vaso", "vaso", "vaso", "gotejador", "canteiro", "calha", "cisterna", "roldana",
                        "prateleira", "estufa", "painel", "bomba", "esteira"],
}


class Estado:
    def __init__(self, escala=1.0):
        self.escala = escala
        self.t = 0
        self.sucata = 0.0
        self.estoque = 0.0
        self.compras = {}          # nome -> quantidade
        self.agua, self.energia, self.transp = "lata", "bicicleta", "balde"
        self.comodos, self.antena = 1, 1
        self.vasos = 3
        self.fila_obra = 0.0       # minutos de obra pendentes (consomem tempo do homem)
        self.historico = {}        # evento -> dia
        self.ocupacao_por_antena = {}
        self.desperdicio = 0.0
        self.vendido = 0.0
        self._occ_acc = [0.0, 0.0]
        self.pagamentos = []       # (dia, item, custo)

    # ---- derivados
    def plots(self):
        n = self.vasos + sum(PLOTS[k] * self.compras.get(k, 0) for k in ("canteiro", "prateleira", "estufa"))
        return n

    def plots_estufa(self):
        return PLOTS["estufa"] * self.compras.get("estufa", 0)

    def demanda(self):
        d = CFG["demanda_radio"][self.antena] + self.comodos
        d += 2 * (self.compras.get("estufa", 0) + self.compras.get("bomba", 0) + self.compras.get("esteira", 0))
        return d

    def oferta(self):
        return CFG["oferta_energia"][self.energia]

    def preco_custo(self, nome):
        base = ITENS[nome][0] if nome in ITENS else ANTENA[self.antena + 1]
        return base * self.escala

    def liberado(self, nome):
        if nome == "antena":
            if self.antena >= 5:
                return False
            en_min, com_min = ANTENA_REQ[self.antena + 1]
            return self.oferta() >= max(en_min, self.demanda() + 1) and self.comodos >= com_min
        custo, ant, com, en = ITENS[nome]
        if self.antena < ant or self.comodos < com:
            return False
        if nome == "vaso":
            return self.vasos < 5
        if nome in MAXQ and self.compras.get(nome, 0) >= MAXQ[nome]:
            return False
        if nome in ("gotejador", "cisterna", "bomba"):
            ordem = ["lata", "gotejador", "cisterna", "bomba"]
            alvo = nome
            if ordem.index(alvo) <= ordem.index(self.agua):
                return False
            if ordem.index(alvo) != ordem.index(self.agua) + 1:
                return False
        if nome in ("moinho", "bateria", "painel"):
            ordem = ["bicicleta", "moinho", "bateria", "painel"]
            if ordem.index(nome) != ordem.index(self.energia) + 1:
                return False
        if nome in ("calha", "roldana", "esteira"):
            ordem = ["balde", "calha", "roldana", "esteira"]
            if ordem.index(nome) != ordem.index(self.transp) + 1:
                return False
        if nome == "comodo2" and self.comodos != 1:
            return False
        if nome == "comodo3" and self.comodos != 2:
            return False
        if nome == "esteira" and self.oferta() < 8:
            return False
        if nome == "bomba" and self.oferta() < 8:
            return False
        if en and self.oferta() < self.demanda() + en:
            return False
        return True

    def aplica(self, nome):
        if nome == "antena":
            self.antena += 1
            return
        self.compras[nome] = self.compras.get(nome, 0) + 1
        if nome == "vaso":
            self.vasos += 1
        elif nome in ("gotejador", "cisterna", "bomba"):
            self.agua = nome
        elif nome in ("moinho", "bateria", "painel"):
            self.energia = nome
        elif nome in ("calha", "roldana", "esteira"):
            self.transp = nome
        elif nome == "comodo2":
            self.comodos = 2
        elif nome == "comodo3":
            self.comodos = 3

    # ---- economia por passo (apenas acordado)
    def restricao(self):
        """Qual limite está mandando agora? 'escotilha' (vazão de venda), 'trabalho' (o homem não dá conta) ou 'producao' (faltam vasos/cultura)."""
        plots = self.plots()
        cultura = "feijao" if self.antena >= 2 else "batata"
        est = self.plots_estufa()
        prod = 0.0
        trab = 0.0
        auto = CFG["rega_automatica"][self.agua]
        carregar = CFG["tarefa_carregar_min"][self.transp]
        for idx in range(plots):
            cult = cultura if idx < plots - est else "tomate"
            ciclo, _ = CULTURAS[cult]
            r = 960.0 / ciclo
            prod += r
            trab += r * (CFG["tarefa_plantar_colher_min"] + carregar + (0 if idx < auto else CFG["tarefa_regar_min"]))
        if self.energia == "bicicleta":
            trab += 960 * CFG["pedalar_fracao"]
        cap = CFG["visitas_por_dia"][self.antena] * CFG["capacidade_escotilha"][self.transp]
        if trab > 960:
            return "trabalho", min(1.0, 960 / trab), prod, cap
        if prod > cap:
            return "escotilha", 1.0, prod, cap
        return "producao", 1.0, prod, cap

    def passo_producao(self, ligado=True):
        plots = self.plots()
        cultura = "feijao" if self.antena >= 2 else "batata"
        plots_est = self.plots_estufa()
        plots_com = plots - plots_est
        auto = CFG["rega_automatica"][self.agua]
        carregar = CFG["tarefa_carregar_min"][self.transp]
        demanda_trabalho = 0.0
        prod = 0.0
        valor = 0.0
        for idx in range(plots):
            if idx < plots_com:
                cult = cultura
            else:
                cult = "tomate"
            ciclo, preco = CULTURAS[cult]
            r = DT / ciclo
            tarefa = CFG["tarefa_plantar_colher_min"] + carregar + (0 if idx < auto else CFG["tarefa_regar_min"])
            demanda_trabalho += r * tarefa
            prod += r
            valor += r * preco
        pedal = DT * CFG["pedalar_fracao"] if self.energia == "bicicleta" else 0.0
        obra = min(self.fila_obra, DT * 0.7)
        demanda_total = demanda_trabalho + pedal + obra
        f = 1.0 if demanda_total <= DT else DT / demanda_total
        self.fila_obra -= obra * f
        self._occ_acc[0] += min(1.0, demanda_total / DT)
        self._occ_acc[1] += 1
        precomed = valor / prod if prod else 0
        self.estoque_valor = getattr(self, "estoque_valor", 0.0)
        self.estoque += prod * f
        self.estoque_valor += valor * f
        K = CFG["capacidade_escotilha"][self.transp]
        if self.estoque > 2 * K:
            sobra = self.estoque - 2 * K
            self.desperdicio += sobra
            self.estoque_valor *= (2 * K) / self.estoque
            self.estoque = 2 * K

    def visita(self):
        K = CFG["capacidade_escotilha"][self.transp]
        if self.estoque <= 0:
            return
        vende = min(self.estoque, K)
        preco_medio = self.estoque_valor / self.estoque if self.estoque else 0
        self.sucata += vende * preco_medio
        self.vendido += vende * preco_medio
        self.estoque -= vende
        self.estoque_valor -= vende * preco_medio


def renda_dia(s):
    """Renda estável em sucata/dia do estado atual (sem compras, sem obra pendente)."""
    c = Estado(s.escala)
    c.__dict__.update({k: (dict(v) if isinstance(v, dict) else list(v) if isinstance(v, list) else v) for k, v in s.__dict__.items()})
    c.fila_obra = 0.0
    c.sucata = 0.0
    c.estoque = 0.0
    c.estoque_valor = 0.0
    c.vendido = 0.0
    for t in range(0, 3 * 1440, DT):
        if ACORDADO[0] <= (t % 1440) < ACORDADO[1]:
            c.passo_producao()
            n = CFG["visitas_por_dia"][c.antena]
            intervalo = 960 / n
            if int(((t % 1440) - ACORDADO[0]) % intervalo) < DT:
                c.visita()
    return c.vendido / 3.0


def simula(politica, escala=1.0, checkins=(8.5, 12.5, 18.5), pc_ligado=None, offline=True, dias=60, detalhado=False):
    """pc_ligado: (hora_ini, hora_fim) em que o PC fica ligado; None = sempre.
    offline=False: o bunker só produz enquanto o PC está ligado."""
    s = Estado(escala)
    ordem = POLITICAS[politica]
    pos = 0
    while s.t < dias * 1440 and s.antena < 5:
        hora = (s.t % 1440) / 60.0
        dia = s.t // 1440
        acordado = ACORDADO[0] <= (s.t % 1440) < ACORDADO[1]
        pc_on = True if pc_ligado is None else (pc_ligado[0] <= hora < pc_ligado[1])
        produz = acordado and (offline or pc_on)
        if produz:
            s.passo_producao()
            # visitas igualmente espaçadas ao longo das 16h
            n = CFG["visitas_por_dia"][s.antena]
            intervalo = 960 / n
            if int(((s.t % 1440) - ACORDADO[0]) % intervalo) < DT:
                s.visita()
        # check-in: só se o jogador está no PC
        if pc_on and any(abs(hora - c) < DT / 120.0 for c in checkins):
            comprou = True
            while comprou:
                comprou = False
                for nome in ordem:
                    if not s.liberado(nome):
                        continue
                    custo = s.preco_custo(nome)
                    if s.sucata < custo:
                        break          # espera juntar: o plano manda
                    renda_antes = renda_dia(s)
                    gargalo_antes = s.restricao()[0]
                    s.sucata -= custo
                    rotulo = nome if nome != "antena" else f"antena{s.antena+1}"
                    if nome == "antena":
                        s.historico[f"antena{s.antena+1}"] = s.t / 1440
                        s.ocupacao_por_antena[s.antena] = s._occ_acc[0] / max(1, s._occ_acc[1])
                        s._occ_acc = [0.0, 0.0]
                    s.aplica(nome)
                    s.fila_obra += 6 + custo / 20.0   # martelar leva tempo real
                    s.pagamentos.append((s.t / 1440, rotulo, custo, renda_dia(s) - renda_antes, renda_dia(s), gargalo_antes, s.restricao()[0]))
                    comprou = True
                    break
        s.t += DT
    s.ocupacao_por_antena[s.antena] = s._occ_acc[0] / max(1, s._occ_acc[1])
    return s


def dia_l5(s):
    return s.historico.get("antena5", None)


def relatorio(escala):
    print(f"=== escala de preços x{escala:.2f} ===")
    for pol in POLITICAS:
        s = simula(pol, escala)
        d = dia_l5(s)
        marcos = ", ".join(f"L{n}: dia {s.historico[f'antena{n}']:.1f}" for n in range(2, 6) if f"antena{n}" in s.historico)
        print(f"{pol:18s} L5 em {d if d is None else round(d,1)} dias | {marcos}")
        print(f"{'':18s} cestos desperdiçados {s.desperdicio:.0f} | sucata vendida {s.vendido:.0f}")
    print()


def cadencia(escala):
    print(f"--- sensibilidade à cadência de check-in (política equilibrada, x{escala:.2f}) ---")
    casos = {
        "1 check-in por dia (18:30)": (18.5,),
        "3 por dia (manhã, almoço, fim do dia)": (8.5, 12.5, 18.5),
        "8 por dia": (8.5, 10, 11.5, 13, 14.5, 16, 17.5, 19),
    }
    for nome, ch in casos.items():
        s = simula("equilibrada", escala, checkins=ch)
        print(f"{nome:42s} L5 em {dia_l5(s):.1f} dias")
    print()


def offline(escala):
    print(f"--- valor do progresso offline (PC ligado 09-18h; política equilibrada, x{escala:.2f}) ---")
    for nome, off in (("com offline (bunker segue de noite e de dia)", True), ("sem offline (só produz com o jogo aberto)", False)):
        s = simula("equilibrada", escala, checkins=(9.5, 12.5, 17.5), pc_ligado=(9, 18), offline=off, dias=200)
        d = dia_l5(s)
        print(f"{nome:46s} L5 em {d if d is None else round(d,1)} dias")
    print()


def ocupacao(escala):
    s = simula("equilibrada", escala)
    print("--- fração do tempo acordado ocupada com tarefas, por nível de antena (equilibrada) ---")
    for n in sorted(s.ocupacao_por_antena):
        print(f"antena {n}: {s.ocupacao_por_antena[n]*100:4.0f}% ocupado")
    print()


def tabela_compras(escala, politica="equilibrada"):
    s = simula(politica, escala)
    print(f"--- ordem, custo e retorno das compras, política {politica} (x{escala:.2f}) ---")
    print("dia   item          custo  renda/dia  ganho/dia  payback  gargalo antes -> depois")
    for dia, item, custo, ganho, renda, g0, g1 in s.pagamentos:
        pb = f"{custo/ganho:5.1f}" if ganho > 0.05 else "   --"
        print(f"{dia:5.1f} {item:11s} {custo:6.0f} {renda:9.0f} {ganho:10.1f} {pb:>8s}  {g0} -> {g1}")
    print()


def grafo():
    """Checa que todo item é alcançável (sem ciclos nem becos) assumindo sucata infinita."""
    s = Estado()
    compradas = []
    mudou = True
    while mudou:
        mudou = False
        for nome in list(ITENS) + ["antena"]:
            while s.liberado(nome):
                s.aplica(nome)
                compradas.append(nome)
                mudou = True
                if nome == "vaso" and s.vasos >= 5:
                    break
    ok = s.antena == 5 and set(ITENS) <= set(compradas)
    faltam = set(ITENS) - set(compradas)
    print("--- checagem do grafo de dependências ---")
    print(f"tudo alcançável com sucata infinita: {ok} | antena final {s.antena} | faltam {sorted(faltam) or 'nada'}")
    print()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--escala", type=float, default=None)
    a = ap.parse_args()
    grafo()
    escalas = [a.escala] if a.escala else [0.7, 1.0, 1.6]
    for e in escalas:
        relatorio(e)
    base = a.escala or 0.7
    cadencia(base)
    offline(base)
    ocupacao(base)
    tabela_compras(base)
    tabela_compras(base, 'antena_primeiro')
