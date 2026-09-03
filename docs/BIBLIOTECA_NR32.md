# Biblioteca de Itens de Inspeção — NR-32

**Projeto InspecionaHU — HU-UFPI**
Fonte normativa única: NR-32 — Segurança e Saúde no Trabalho em Serviços de Saúde (Portaria MTb n.º 485/2005, com alterações até a Portaria MTP n.º 4.219/2022), conforme o texto em `docs/nr32_texto.md` (extraído de `docs/nr32.pdf`).

Este documento define o catálogo de itens de inspeção do aplicativo (Parte A) e os templates de checklist por tipo de setor (Parte B). Ele é a base dos templates globais carregados no banco de dados e deve ser validado pelo SESMT antes do uso em produção.

## Convenções adotadas

- **Todo item corresponde a uma cláusula literal da NR-32**, citada pelo número exato. Nenhum item foi criado a partir de NR-23, NR-17, NR-06, NR-24, RDC ou NBR, mesmo quando a NR-32 as cita por referência cruzada (os casos cogitados e rejeitados estão na seção "Itens descartados").
- **Descrição**: frase afirmativa, verificável em campo por observação direta ou conferência de documento presente no setor. O inspetor marca **Conforme / Não conforme / Não aplicável**.
- **Criticidade `critical`**: quando a cláusula usa vedação ("é vedado", "não é permitido"), obrigação imediata, ou quando a não conformidade implica exposição direta do trabalhador (agente biológico, perfurocortante, radiação ionizante, quimioterápico antineoplásico). Itens de registro, prazo de guarda e documentação são `normal`, mesmo nas seções 32.4 e Anexo III — para preservar o valor de destaque da não conformidade crítica.
- **Exige foto**: **sim** para item de estrutura física ou condição observável que a foto comprova; **não** para item de natureza documental, independentemente da criticidade.
- Um mesmo ID é reutilizado em vários templates da Parte B sem duplicação de texto.

---

## PARTE A — Catálogo de itens por seção da norma

### 32.2 Riscos Biológicos (BIO)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| BIO-01 | Lavatório exclusivo para higiene das mãos com água corrente, sabonete líquido, toalha descartável e lixeira com abertura sem contato manual | 32.2.4.3 | normal | Sim |
| BIO-02 | Quartos ou enfermarias de isolamento de doenças infectocontagiosas possuem lavatório em seu interior | 32.2.4.3.1 | normal | Sim |
| BIO-03 | Ausência de alimentos e bebidas nos postos de trabalho e de guarda de alimentos em locais não destinados a esse fim | 32.2.4.5 | critical | Sim |
| BIO-04 | Trabalhadores sem adornos, sem manuseio de lentes de contato e sem fumar nos postos de trabalho | 32.2.4.5 | critical | Sim |
| BIO-05 | Trabalhadores utilizando calçados fechados | 32.2.4.5 | critical | Sim |
| BIO-06 | Trabalhadores utilizando vestimenta de trabalho adequada e em condições de conforto | 32.2.4.6 | normal | Sim |
| BIO-07 | EPI descartáveis ou não disponíveis em número suficiente nos postos de trabalho, com fornecimento ou reposição imediata garantida | 32.2.4.7 | normal | Sim |
| BIO-08 | Locais apropriados para fornecimento de vestimentas limpas e para deposição das usadas | 32.2.4.6.3 | normal | Sim |
| BIO-09 | Comprovante de capacitação dos trabalhadores disponível no setor, com data, carga horária, conteúdo ministrado e identificação do instrutor | 32.2.4.9.2 | normal | Não |
| BIO-10 | Instruções escritas, em linguagem acessível, das rotinas do local de trabalho e das medidas de prevenção disponíveis aos trabalhadores | 32.2.4.10 | normal | Não |
| BIO-11 | Colchões, colchonetes e demais almofadados revestidos de material lavável e impermeável, sem furos, rasgos, sulcos ou reentrâncias | 32.2.4.13 | normal | Sim |
| BIO-12 | Trabalhadores do setor possuem comprovante das vacinas recebidas | 32.2.4.17.7 | normal | Não |

### 32.3 Riscos Químicos (QUI)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| QUI-01 | Rotulagem do fabricante mantida na embalagem original dos produtos químicos | 32.3.1 | normal | Sim |
| QUI-02 | Recipientes de produtos químicos manipulados ou fracionados identificados com etiqueta legível (nome, composição, concentração, data de envase e validade, responsável) | 32.3.2 | normal | Sim |
| QUI-03 | Embalagens de produtos químicos não são reutilizadas | 32.3.3 | critical | Sim |
| QUI-04 | Cópia da ficha descritiva dos produtos químicos de risco mantida no local onde o produto é utilizado | 32.3.4.1.2 | normal | Não |
| QUI-05 | Chuveiro de emergência e lava-olhos presentes no local de manipulação ou fracionamento de produtos químicos | 32.3.7.1.3 | normal | Sim |
| QUI-06 | Manipulação ou fracionamento de produtos químicos realizado somente em local apropriado destinado a esse fim | 32.3.7.1.1 | critical | Sim |
| QUI-07 | Áreas de armazenamento de produtos químicos ventiladas e sinalizadas | 32.3.7.6 | normal | Sim |
| QUI-08 | Áreas de armazenamento próprias e separadas para produtos químicos incompatíveis | 32.3.7.6.1 | normal | Sim |
| QUI-09 | Cilindros de gases com identificação do gás e válvula de segurança, sem vazamentos | 32.3.8.2 | critical | Sim |
| QUI-10 | Cilindros de gases inflamáveis armazenados a no mínimo 8 metros dos oxidantes ou separados por barreira vedada e resistente ao fogo | 32.3.8.3 | normal | Sim |
| QUI-11 | Placas do sistema centralizado de gases medicinais fixadas em local visível, com pessoas autorizadas, procedimentos e telefone de emergência e sinalização de perigo | 32.3.8.4 | normal | Sim |
| QUI-12 | Quimioterápicos antineoplásicos preparados em área exclusiva e com acesso restrito aos profissionais diretamente envolvidos | 32.3.9.4.1 | critical | Sim |
| QUI-13 | Cabine de Segurança Biológica Classe II B2 na sala de preparo, com etiquetas visíveis das datas da última e da próxima manutenção | 32.3.9.4.5.1 | critical | Sim |
| QUI-14 | Kit de derramamento identificado e disponível nas áreas de preparação, armazenamento, administração e transporte de quimioterápicos | 32.3.9.4.9.3 | critical | Sim |

### 32.4 Radiações Ionizantes (RAD)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| RAD-01 | Plano de Proteção Radiológica (PPR) mantido no local de trabalho e à disposição, dentro do prazo de vigência | 32.4.2 | normal | Não |
| RAD-02 | Trabalhadores em áreas com fontes de radiação ionizante sob monitoração individual de dose (dosímetro em uso) | 32.4.3 | critical | Sim |
| RAD-03 | Áreas da instalação radiativa sinalizadas com o símbolo internacional de presença de radiação nos acessos controlados | 32.4.12 | critical | Sim |
| RAD-04 | Sala de manipulação e armazenamento de fontes com revestimento impermeável, bancadas lisas recobertas, pia com cuba de no mínimo 40 cm e torneiras sem controle manual | 32.4.13.2 | normal | Sim |
| RAD-05 | Ausência de alimentos, bebidas, cosméticos e bens pessoais nos locais onde são manipulados ou armazenados materiais radioativos ou rejeitos | 32.4.13.2.2 | critical | Sim |
| RAD-06 | Local de decaimento de rejeitos radioativos em área de acesso controlado, sinalizado, com blindagem adequada e compartimentos de segregação | 32.4.13.6 | critical | Sim |
| RAD-07 | Quarto de internação para administração de radiofármacos com blindagem, sanitário privativo, biombo blindado junto ao leito, sinalização externa e acesso controlado | 32.4.13.7 | critical | Sim |
| RAD-08 | Salas de tratamento de radioterapia com portas com sistema de intertravamento e indicadores luminosos de equipamento em operação (interno e externo) | 32.4.14.1 | critical | Sim |
| RAD-09 | Alvará de Funcionamento vigente e Programa de Garantia da Qualidade mantidos no local de trabalho (radiodiagnóstico) | 32.4.15.1 | normal | Não |
| RAD-10 | Sala de raios X com sinalização nas portas de acesso (símbolo internacional e inscrição de entrada restrita) e sinalização luminosa vermelha com aviso de advertência | 32.4.15.3 | critical | Sim |
| RAD-11 | Equipamentos móveis de raios X com cabo disparador de comprimento mínimo de 2 metros | 32.4.15.6 | critical | Sim |
| RAD-12 | Equipamentos de fluoroscopia com cortina ou saiote plumbífero inferior e lateral e sistema de alarme de nível de dose | 32.4.15.8 | critical | Sim |

### 32.5 Resíduos (RES)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| RES-01 | Sacos de resíduos preenchidos até no máximo 2/3 da capacidade, fechados sem permitir derramamento e retirados imediatamente do local de geração após o fechamento | 32.5.2 | normal | Sim |
| RES-02 | Segregação dos resíduos realizada no local de geração, com recipientes em número suficiente e próximos da fonte geradora | 32.5.3 | normal | Sim |
| RES-03 | Recipientes de resíduos laváveis, resistentes, com tampa provida de abertura sem contato manual, cantos arredondados, identificados e sinalizados | 32.5.3 | normal | Sim |
| RES-04 | Recipientes de perfurocortantes preenchidos até no máximo 5 cm abaixo do bocal | 32.5.3.2 | critical | Sim |
| RES-05 | Recipiente de perfurocortantes mantido em suporte exclusivo e em altura que permita visualizar a abertura para descarte | 32.5.3.2.1 | critical | Sim |
| RES-06 | Transporte manual do recipiente de segregação sem contato com outras partes do corpo e sem arrasto | 32.5.4 | critical | Sim |
| RES-07 | Sala de armazenamento temporário com pisos e paredes laváveis, ralo sifonado, ventilação adequada, limpa, sinalizada e contendo somente recipientes de coleta/armazenamento/transporte | 32.5.6 | normal | Sim |
| RES-08 | Carros de transporte de resíduos de material rígido, lavável, impermeável, com tampa articulada e cantos arredondados | 32.5.7 | normal | Sim |
| RES-09 | Transporte de resíduos realizado em sentido único, com roteiro definido, em horários não coincidentes com distribuição de roupas, alimentos, medicamentos ou períodos de visita | 32.5.7 | normal | Não |
| RES-10 | Local de armazenamento externo de resíduos dimensionado de forma a permitir a separação dos recipientes conforme o tipo de resíduo | 32.5.8.1 | normal | Sim |

### 32.6 Conforto por Ocasião das Refeições (REF)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| REF-01 | Local para refeições localizado fora da área do posto de trabalho | 32.6.2 | normal | Sim |
| REF-02 | Local para refeições com piso lavável | 32.6.2 | normal | Sim |
| REF-03 | Local para refeições limpo, arejado e com boa iluminação | 32.6.2 | normal | Sim |
| REF-04 | Mesas e assentos dimensionados de acordo com o número de trabalhadores por intervalo de descanso e refeição | 32.6.2 | normal | Sim |
| REF-05 | Lavatórios instalados nas proximidades ou no próprio local de refeições | 32.6.2 | normal | Sim |
| REF-06 | Fornecimento de água potável no local de refeições | 32.6.2 | normal | Sim |
| REF-07 | Equipamento apropriado e seguro para aquecimento de refeições | 32.6.2 | normal | Sim |
| REF-08 | Lavatórios para higiene das mãos providos de papel toalha, sabonete líquido e lixeira com tampa acionada por pedal | 32.6.3 | normal | Sim |

### 32.7 Lavanderias (LAV)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| LAV-01 | Lavanderia com duas áreas distintas: uma suja e outra limpa | 32.7.1 | normal | Sim |
| LAV-02 | Recebimento, classificação, pesagem e lavagem ocorrendo na área suja; manipulação de roupas lavadas ocorrendo na área limpa | 32.7.1 | normal | Sim |
| LAV-03 | Máquinas de lavar de porta dupla ou de barreira | 32.7.2 | normal | Sim |
| LAV-04 | Roupa inserida pela porta da área suja por um operador e retirada na área limpa por outro operador | 32.7.2 | normal | Não |
| LAV-05 | Comunicação entre as áreas suja e limpa realizada somente por visores ou intercomunicadores | 32.7.2.1 | normal | Sim |
| LAV-06 | Calandra com termômetro para cada câmara de aquecimento e termostato | 32.7.3 | normal | Sim |
| LAV-07 | Calandra com dispositivo de proteção que impeça a inserção de segmentos corporais junto aos cilindros ou partes móveis | 32.7.3 | normal | Sim |
| LAV-08 | Máquinas de lavar, centrífugas e secadoras dotadas de dispositivos eletromecânicos que interrompem o funcionamento na abertura dos compartimentos | 32.7.4 | normal | Sim |

### 32.8 Limpeza e Conservação (LIM)

> Nota: a seção 32.8 da norma possui apenas 3 itens normativos (32.8.1 a 32.8.3). Foram extraídos os 6 itens verificáveis em campo — quantidade abaixo da faixa de 8 a 14, priorizando qualidade sobre quantidade, conforme critério do projeto.

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| LIM-01 | Comprovação da capacitação dos trabalhadores de limpeza mantida no local de trabalho | 32.8.1.1 | normal | Não |
| LIM-02 | Carro funcional disponível para guarda e transporte dos materiais e produtos de limpeza | 32.8.2 | normal | Sim |
| LIM-03 | Materiais e utensílios de limpeza que preservam a integridade física do trabalhador | 32.8.2 | normal | Sim |
| LIM-04 | Ausência de varrição seca nas áreas internas | 32.8.2 | critical | Sim |
| LIM-05 | Trabalhadores de limpeza sem uso de adornos | 32.8.2 | critical | Sim |
| LIM-06 | Comprovação de capacitação dos trabalhadores de empresa terceirizada de limpeza disponível | 32.8.3 | normal | Não |

### 32.9 Manutenção de Máquinas e Equipamentos (MAN)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| MAN-01 | Equipamentos submetidos a prévia descontaminação antes da realização de manutenção | 32.9.2 | critical | Sim |
| MAN-02 | Registros de inspeção prévia e manutenção preventiva de máquinas, equipamentos e ferramentas disponíveis aos trabalhadores | 32.9.3.1 | normal | Não |
| MAN-03 | Cronograma de manutenção preventiva do sistema de abastecimento de gases e das capelas, com registro individual assinado pelo profissional executor | 32.9.3.3 | normal | Não |
| MAN-04 | Equipamentos e meios mecânicos de transporte com sistemas de rodízio em perfeito estado de funcionamento | 32.9.4 | normal | Sim |
| MAN-05 | Dispositivos de ajuste dos leitos com manutenção preventiva e lubrificação permanente, operando sem sobrecarga para os trabalhadores | 32.9.5 | normal | Sim |
| MAN-06 | Registros de manutenção preventiva e corretiva dos sistemas de climatização disponíveis | 32.9.6 | normal | Não |
| MAN-07 | Comprovação de capacitação inicial e continuada dos trabalhadores de manutenção disponível | 32.9.1 | normal | Não |
| MAN-08 | Procedimentos de segurança documentados para manutenção de equipamentos cuja descontinuidade de uso acarrete risco à vida do paciente | 32.9.2.1 | normal | Não |

### 32.10 Disposições Gerais (GER)

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| GER-01 | Ambientes de trabalho mantidos em condições de limpeza e conservação | 32.10.1 | normal | Sim |
| GER-02 | Comprovação de capacitação dos operadores quanto ao modo de operação e riscos dos equipamentos, anterior à utilização | 32.10.3 | normal | Não |
| GER-03 | Manuais dos fabricantes de equipamentos e máquinas, impressos em língua portuguesa, disponíveis aos trabalhadores envolvidos | 32.10.4 | normal | Não |
| GER-04 | Material médico-hospitalar utilizado de acordo com as recomendações de uso e especificações técnicas do manual ou da embalagem | 32.10.5 | critical | Sim |
| GER-05 | Comprovação do programa de controle de animais sinantrópicos disponível | 32.10.6 | normal | Não |
| GER-06 | Cozinha dotada de sistema de exaustão e equipamentos que reduzam a dispersão de gorduras e vapores | 32.10.7 | normal | Sim |
| GER-07 | Dispositivos seguros e com estabilidade disponíveis para acesso a locais altos sem esforço adicional | 32.10.9 | normal | Sim |
| GER-08 | Dispositivos que minimizem o esforço dos trabalhadores disponíveis para movimentação e transporte de pacientes | 32.10.10 | normal | Sim |
| GER-09 | Ausência da prática de pipetagem com a boca | 32.10.14 | critical | Sim |
| GER-10 | Lavatórios e pias com torneiras ou comandos que dispensam o contato das mãos no fechamento, providos de sabão líquido e toalhas descartáveis | 32.10.15 | normal | Sim |
| GER-11 | Ambientes onde são realizados procedimentos com odores fétidos providos de sistema de exaustão ou dispositivo que os minimize | 32.10.13 | normal | Sim |

### Anexo III — Perfurocortantes (PFC)

> Nota: os itens 32.2.4.14, 32.2.4.15 e 32.2.4.16 pertencem à seção 32.2 da norma, mas tratam exclusivamente de perfurocortantes e foram agrupados aqui por coerência temática; a referência citada permanece a original.

| ID | Descrição do item | Referência | Criticidade | Exige foto |
|----|-------------------|------------|-------------|------------|
| PFC-01 | Ausência da prática de reencape e de desconexão manual de agulhas | 32.2.4.15 | critical | Sim |
| PFC-02 | Descarte de objetos perfurocortantes realizado pelo próprio trabalhador que os utilizou | 32.2.4.14 | critical | Sim |
| PFC-03 | Materiais perfurocortantes com dispositivo de segurança em uso, quando existente, disponível e tecnicamente possível | Anexo III item 5.1 | critical | Sim |
| PFC-04 | Coletores de descarte de perfurocortantes disponíveis nos pontos de uso (controle de engenharia) | Anexo III item 5.1 | critical | Sim |
| PFC-05 | Plano de Prevenção de Riscos de Acidentes com Materiais Perfurocortantes elaborado e disponível | 32.2.4.16 | normal | Não |
| PFC-06 | Cronograma de implementação do plano de prevenção e comprovação da implantação disponíveis | Anexo III item 8.3 | normal | Não |
| PFC-07 | Comprovação da capacitação para prevenção de acidentes com perfurocortantes, com data, carga horária, conteúdo e identificação do instrutor | Anexo III item 7.2 | normal | Não |
| PFC-08 | Procedimentos de registro e investigação de acidentes e situações de risco com perfurocortantes implantados e documentados | Anexo III item 3.3 | normal | Não |

---

## PARTE B — Templates por tipo de setor

Cada template combina itens de mais de uma seção da norma. Um mesmo ID aparece em vários setores por definição — o catálogo da Parte A é a fonte única do texto.

### Lavanderia
Escopo: processamento de roupas hospitalares, do recebimento de roupa suja à expedição de roupa limpa.
IDs: LAV-01, LAV-02, LAV-03, LAV-04, LAV-05, LAV-06, LAV-07, LAV-08, BIO-01, BIO-05, BIO-06, BIO-07, BIO-09, QUI-01, QUI-04, RES-01, RES-03, GER-01, GER-10

### Centro Cirúrgico
Escopo: salas cirúrgicas e áreas de apoio, com exposição biológica direta, perfurocortantes e gases medicinais/anestésicos.
IDs: BIO-01, BIO-03, BIO-04, BIO-05, BIO-06, BIO-07, BIO-10, QUI-09, QUI-11, PFC-01, PFC-02, PFC-03, PFC-04, RES-01, RES-04, RES-05, MAN-01, GER-01, GER-04, GER-10

### CME (Central de Material e Esterilização)
Escopo: recepção, limpeza, desinfecção e esterilização de materiais e instrumentais.
IDs: BIO-01, BIO-03, BIO-05, BIO-06, BIO-07, BIO-09, QUI-01, QUI-02, QUI-03, QUI-04, QUI-06, MAN-01, MAN-02, MAN-03, PFC-01, PFC-04, RES-04, GER-01, GER-04, GER-10

### Enfermaria
Escopo: unidades de internação com assistência direta ao paciente.
IDs: BIO-01, BIO-02, BIO-03, BIO-04, BIO-05, BIO-06, BIO-07, BIO-10, BIO-11, PFC-01, PFC-02, PFC-04, RES-01, RES-02, RES-03, RES-04, RES-05, MAN-05, GER-01, GER-08, GER-10

### Laboratório
Escopo: análises clínicas e manipulação de material biológico e químico.
IDs: BIO-01, BIO-03, BIO-04, BIO-05, BIO-06, BIO-07, BIO-09, BIO-10, QUI-01, QUI-02, QUI-03, QUI-04, QUI-05, QUI-06, QUI-07, QUI-08, PFC-01, PFC-04, RES-04, RES-05, GER-01, GER-09, GER-10

### Farmácia e Quimioterapia
Escopo: armazenamento, fracionamento e preparo de medicamentos, incluindo quimioterápicos antineoplásicos.
IDs: QUI-01, QUI-02, QUI-03, QUI-04, QUI-05, QUI-06, QUI-07, QUI-08, QUI-12, QUI-13, QUI-14, BIO-01, BIO-03, BIO-06, BIO-07, PFC-01, PFC-03, PFC-04, RES-04, GER-01, GER-10

### Radiologia e Medicina Nuclear
Escopo: serviços com radiação ionizante — radiodiagnóstico, medicina nuclear e radioterapia.
IDs: RAD-01, RAD-02, RAD-03, RAD-04, RAD-05, RAD-06, RAD-07, RAD-08, RAD-09, RAD-10, RAD-11, RAD-12, BIO-01, BIO-03, BIO-07, RES-01, GER-01, GER-10

### Nutrição e Cozinha
Escopo: preparo e distribuição de alimentos e áreas de refeição dos trabalhadores.
IDs: REF-01, REF-02, REF-03, REF-04, REF-05, REF-06, REF-07, REF-08, GER-06, GER-05, GER-01, GER-07, GER-10, QUI-01, QUI-04, RES-01, RES-02, RES-03

### Limpeza e Conservação
Escopo: higienização dos ambientes do serviço de saúde, própria ou terceirizada.
IDs: LIM-01, LIM-02, LIM-03, LIM-04, LIM-05, LIM-06, BIO-05, BIO-06, BIO-07, BIO-09, QUI-01, QUI-02, QUI-04, RES-01, RES-02, RES-03, RES-06, GER-01, GER-10

### Manutenção
Escopo: manutenção predial e de máquinas e equipamentos do serviço de saúde.
IDs: MAN-01, MAN-02, MAN-03, MAN-04, MAN-05, MAN-06, MAN-07, MAN-08, BIO-06, BIO-07, BIO-09, QUI-01, QUI-04, QUI-09, QUI-10, GER-01, GER-03, GER-07

### Resíduos
Escopo: segregação, acondicionamento, transporte interno e armazenamento de resíduos de serviços de saúde.
IDs: RES-01, RES-02, RES-03, RES-04, RES-05, RES-06, RES-07, RES-08, RES-09, RES-10, PFC-04, BIO-05, BIO-06, BIO-07, QUI-03, GER-01

---

## Itens descartados

Itens cogitados e **não criados**, com o motivo:

| Item cogitado | Motivo do descarte |
|---------------|--------------------|
| "Extintor de incêndio dentro da validade" (presente no seed atual) | Proteção contra incêndio é matéria da **NR-23**. Não há cláusula correspondente na NR-32. Será removido do seed. |
| "Rota de fuga desobstruída" (presente no seed atual) | Saídas de emergência são matéria da **NR-23**. Não há cláusula correspondente na NR-32. Será removido do seed. |
| Categoria/itens de "Radiações Não Ionizantes" | Não existe seção sobre radiações não ionizantes na NR-32 vigente. |
| Categoria/itens de "Ergonomia" (mobiliário, postura, pausas) | Matéria da **NR-17**. O item 32.10.8 ("postos organizados de forma a evitar deslocamentos e esforços adicionais") existe na NR-32, mas não é verificável objetivamente numa inspeção visual — descartado por baixa verificabilidade. |
| "Refeitório em conformidade com a NR-24" | O item 32.6.1 apenas remete à **NR-24**; os requisitos verificáveis próprios da NR-32 estão em 32.6.2/32.6.3 (aproveitados em REF-01 a REF-08). |
| "Níveis de ruído/iluminação/conforto térmico adequados" (32.10.1 a–c) | As alíneas remetem a **NB 95, NB 57 e RDC 50** e exigem medição instrumental, não inspeção visual. Apenas a alínea d (limpeza e conservação) foi aproveitada (GER-01). |
| "Edificação em conformidade com a RDC 50/2002" (32.10.16) | Requisito de norma **ANVISA** por referência cruzada; verificação de projeto arquitetônico, fora do alcance de inspeção de rotina. |
| "Esterilização por óxido de etileno conforme Portaria 482/1999" (32.3.7.4) | A cláusula remete a portaria interministerial específica; a verificação é documental-regulatória, não inspecionável visualmente no setor. |
| "Sacos de resíduos em conformidade com a NBR 9191" (32.5.2 caput) | A conformidade com a **NBR** exige ensaio; RES-01 aproveita apenas os requisitos verificáveis em campo da própria cláusula (preenchimento a 2/3, fechamento, retirada imediata). |
| "Recipientes de resíduos conforme normas da ABNT" (32.5.3 a) | Conformidade **ABNT** não é verificável visualmente; RES-02/RES-03 aproveitam os requisitos descritos literalmente na cláusula. |
| "O empregador assegura capacitação continuada" (32.2.4.9 e similares) | Obrigação de gestão não observável no local. Substituída pelos itens documentais verificáveis: comprovantes de capacitação (BIO-09, LIM-01, MAN-07, PFC-07, GER-02). |
| "Sinalização conforme NR-26" (32.3.7.1.3 a) | A alínea remete à **NR-26**; a existência de sinalização é coberta por QUI-07 sem invocar norma externa. |
| "Concentração de químicos abaixo dos limites das NR-09/NR-15" (32.3.7.1.3 b) | Exige avaliação quantitativa de higiene ocupacional (medição), não inspeção visual. |
| "Rejeitos radioativos tratados conforme Resolução CNEN NE-6.05" (32.5.9) | Remete a resolução **CNEN**; o local de decaimento verificável em campo está coberto por RAD-06. |
