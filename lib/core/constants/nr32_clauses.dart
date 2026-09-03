/// Texto integral das cláusulas da NR-32 referenciadas pela biblioteca de
/// itens de inspeção (docs/BIBLIOTECA_NR32.md).
///
/// Fonte: docs/nr32_texto.md, extraído de docs/nr32.pdf (NR-32 — Portaria
/// MTb n.º 485/2005, com alterações até a Portaria MTP n.º 4.219/2022).
/// Texto literal da norma, sem paráfrase; apenas as anotações editoriais
/// de portaria ("Alterado pela Portaria...") foram omitidas.
///
/// A chave é exatamente o valor gravado em `nr32_reference` nos itens de
/// checklist/template. Referência ausente neste mapa: o chip NR-32 é
/// exibido, mas não é tocável.
const Map<String, String> nr32Clauses = {
  // ── 32.2 Riscos Biológicos ────────────────────────────────────────────
  '32.2.4.3':
      'Todo local onde exista possibilidade de exposição ao agente biológico deve ter lavatório exclusivo para higiene das mãos provido de água corrente, sabonete líquido, toalha descartável e lixeira provida de sistema de abertura sem contato manual.',
  '32.2.4.3.1':
      'Os quartos ou enfermarias destinados ao isolamento de pacientes portadores de doenças infecto-contagiosas devem conter lavatório em seu interior.',
  '32.2.4.5':
      'O empregador deve vedar:\na) a utilização de pias de trabalho para fins diversos dos previstos;\nb) o ato de fumar, o uso de adornos e o manuseio de lentes de contato nos postos de trabalho;\nc) o consumo de alimentos e bebidas nos postos de trabalho;\nd) a guarda de alimentos em locais não destinados para este fim;\ne) o uso de calçados abertos.',
  '32.2.4.6':
      'Todos trabalhadores com possibilidade de exposição a agentes biológicos devem utilizar vestimenta de trabalho adequada e em condições de conforto.',
  '32.2.4.6.3':
      'O empregador deve providenciar locais apropriados para fornecimento de vestimentas limpas e para deposição das usadas.',
  '32.2.4.7':
      'Os Equipamentos de Proteção Individual - EPI, descartáveis ou não, deverão estar à disposição em número suficiente nos postos de trabalho, de forma que seja garantido o imediato fornecimento ou reposição.',
  '32.2.4.9.2':
      'O empregador deve comprovar para a inspeção do trabalho a realização da capacitação através de documentos que informem a data, o horário, a carga horária, o conteúdo ministrado, o nome e a formação ou capacitação profissional do instrutor e dos trabalhadores envolvidos.',
  '32.2.4.10':
      'Em todo local onde exista a possibilidade de exposição a agentes biológicos, devem ser fornecidas aos trabalhadores instruções escritas, em linguagem acessível, das rotinas realizadas no local de trabalho e medidas de prevenção de acidentes e de doenças relacionadas ao trabalho.',
  '32.2.4.13':
      'Os colchões, colchonetes e demais almofadados devem ser revestidos de material lavável e impermeável, permitindo desinfecção e fácil higienização.',
  '32.2.4.14':
      'Os trabalhadores que utilizarem objetos perfurocortantes devem ser os responsáveis pelo seu descarte.',
  '32.2.4.15': 'São vedados o reencape e a desconexão manual de agulhas.',
  '32.2.4.16':
      'O empregador deve elaborar e implementar Plano de Prevenção de Riscos de Acidentes com Materiais Perfurocortantes, conforme as diretrizes estabelecidas no Anexo III desta Norma Regulamentadora.',
  '32.2.4.17.7':
      'Deve ser fornecido ao trabalhador comprovante das vacinas recebidas.',

  // ── 32.3 Riscos Químicos ──────────────────────────────────────────────
  '32.3.1':
      'Deve ser mantida a rotulagem do fabricante na embalagem original dos produtos químicos utilizados em serviços de saúde.',
  '32.3.2':
      'Todo recipiente contendo produto químico manipulado ou fracionado deve ser identificado, de forma legível, por etiqueta com o nome do produto, composição química, sua concentração, data de envase e de validade, e nome do responsável pela manipulação ou fracionamento.',
  '32.3.3':
      'É vedado o procedimento de reutilização das embalagens de produtos químicos.',
  '32.3.4.1.2':
      'Uma cópia da ficha deve ser mantida nos locais onde o produto é utilizado.',
  '32.3.7.1.1':
      'É vedada a realização destes procedimentos em qualquer local que não o apropriado para este fim.',
  '32.3.7.1.3':
      'O local deve dispor, no mínimo, de:\na) sinalização gráfica de fácil visualização para identificação do ambiente, respeitando o disposto na NR-26;\nb) equipamentos que garantam a concentração dos produtos químicos no ar abaixo dos limites de tolerância estabelecidos nas NR-09 e NR-15 e observando-se os níveis de ação previstos na NR-09;\nc) equipamentos que garantam a exaustão dos produtos químicos de forma a não potencializar a exposição de qualquer trabalhador, envolvido ou não, no processo de trabalho, não devendo ser utilizado o equipamento tipo coifa;\nd) chuveiro e lava-olhos, os quais deverão ser acionados e higienizados semanalmente;\ne) equipamentos de proteção individual, adequados aos riscos, à disposição dos trabalhadores;\nf) sistema adequado de descarte.',
  '32.3.7.6':
      'As áreas de armazenamento de produtos químicos devem ser ventiladas e sinalizadas.',
  '32.3.7.6.1':
      'Devem ser previstas áreas de armazenamento próprias para produtos químicos incompatíveis.',
  '32.3.8.2':
      'É vedado:\na) a utilização de equipamentos em que se constate vazamento de gás;\nb) submeter equipamentos a pressões superiores àquelas para as quais foram projetados;\nc) a utilização de cilindros que não tenham a identificação do gás e a válvula de segurança;\nd) a movimentação dos cilindros sem a utilização dos equipamentos de proteção individual adequados;\ne) a submissão dos cilindros a temperaturas extremas;\nf) a utilização do oxigênio e do ar comprimido para fins diversos aos que se destinam;\ng) o contato de óleos, graxas, hidrocarbonetos ou materiais orgânicos similares com gases oxidantes;\nh) a utilização de cilindros de oxigênio sem a válvula de retenção ou o dispositivo apropriado para impedir o fluxo reverso;\ni) a transferência de gases de um cilindro para outro, independentemente da capacidade dos cilindros;\nj) o transporte de cilindros soltos, em posição horizontal e sem capacetes.',
  '32.3.8.3':
      'Os cilindros contendo gases inflamáveis, tais como hidrogênio e acetileno, devem ser armazenados a uma distância mínima de oito metros daqueles contendo gases oxidantes, tais como oxigênio e óxido nitroso, ou através de barreiras vedadas e resistentes ao fogo.',
  '32.3.8.4':
      'Para o sistema centralizado de gases medicinais devem ser fixadas placas, em local visível, com caracteres indeléveis e legíveis, com as seguintes informações:\na) nominação das pessoas autorizadas a terem acesso ao local e treinadas na operação e manutenção do sistema;\nb) procedimentos a serem adotados em caso de emergência;\nc) número de telefone para uso em caso de emergência;\nd) sinalização alusiva a perigo.',
  '32.3.9.4.1':
      'Os quimioterápicos antineoplásicos somente devem ser preparados em área exclusiva e com acesso restrito aos profissionais diretamente envolvidos. A área deve dispor no mínimo de:\na) vestiário de barreira com dupla câmara;\nb) sala de preparo dos quimioterápicos;\nc) local destinado para as atividades administrativas;\nd) local de armazenamento exclusivo para estocagem.',
  '32.3.9.4.5.1':
      'A cabine deve:\na) estar em funcionamento no mínimo por 30 minutos antes do início do trabalho de manipulação e permanecer ligada por 30 minutos após a conclusão do trabalho;\nb) ser submetida periodicamente a manutenções e trocas de filtros absolutos e pré-filtros de acordo com um programa escrito, que obedeça às especificações do fabricante, e que deve estar à disposição da inspeção do trabalho;\nc) possuir relatório das manutenções, que deve ser mantido a disposição da fiscalização do trabalho;\nd) ter etiquetas afixadas em locais visíveis com as datas da última e da próxima manutenção;\ne) ser submetida a processo de limpeza, descontaminação e desinfecção, nas paredes laterais internas e superfície de trabalho, antes do início das atividades;\nf) ter a sua superfície de trabalho submetida aos procedimentos de limpeza ao final das atividades e no caso de ocorrência de acidentes com derramamentos e respingos.',
  '32.3.9.4.9.3':
      'Nas áreas de preparação, armazenamento e administração e para o transporte deve ser mantido um "Kit" de derramamento identificado e disponível, que deve conter, no mínimo: luvas de procedimento, avental impermeável, compressas absorventes, proteção respiratória, proteção ocular, sabão, recipiente identificado para recolhimento de resíduos e descrição do procedimento.',

  // ── 32.4 Radiações Ionizantes ─────────────────────────────────────────
  '32.4.2':
      'É obrigatório manter no local de trabalho e à disposição da inspeção do trabalho o Plano de Proteção Radiológica - PPR, aprovado pela CNEN, e para os serviços de radiodiagnóstico aprovado pela Vigilância Sanitária.',
  '32.4.3':
      'O trabalhador que realize atividades em áreas onde existam fontes de radiações ionizantes deve:\na) permanecer nestas áreas o menor tempo possível para a realização do procedimento;\nb) ter conhecimento dos riscos radiológicos associados ao seu trabalho;\nc) estar capacitado inicialmente e de forma continuada em proteção radiológica;\nd) usar os EPI adequados para a minimização dos riscos;\ne) estar sob monitoração individual de dose de radiação ionizante, nos casos em que a exposição seja ocupacional.',
  '32.4.12':
      'As áreas da instalação radiativa devem estar devidamente sinalizadas em conformidade com a legislação em vigor, em especial quanto aos seguintes aspectos:\na) utilização do símbolo internacional de presença de radiação nos acessos controlados;\nb) as fontes presentes nestas áreas e seus rejeitos devem ter as suas embalagens, recipientes ou blindagens identificadas em relação ao tipo de elemento radioativo, atividade e tipo de emissão;\nc) valores das taxas de dose e datas de medição em pontos de referência significativos, próximos às fontes de radiação, nos locais de permanência e de trânsito dos trabalhadores, em conformidade com o disposto no PPR;\nd) identificação de vias de circulação, entrada e saída para condições normais de trabalho e para situações de emergência;\ne) localização dos equipamentos de segurança;\nf) procedimentos a serem obedecidos em situações de acidentes ou de emergência;\ng) sistemas de alarme.',
  '32.4.13.2':
      'A sala de manipulação e armazenamento de fontes radioativas em uso deve:\na) ser revestida com material impermeável que possibilite sua descontaminação, devendo os pisos e paredes ser providos de cantos arredondados;\nb) possuir bancadas constituídas de material liso, de fácil descontaminação, recobertas com plástico e papel absorvente;\nc) dispor de pia com cuba de, no mínimo, 40 cm de profundidade, e acionamento para abertura das torneiras sem controle manual.',
  '32.4.13.2.2':
      'Nos locais onde são manipulados e armazenados materiais radioativos ou rejeitos, não é permitido:\na) aplicar cosméticos, alimentar-se, beber, fumar e repousar;\nb) guardar alimentos, bebidas e bens pessoais.',
  '32.4.13.6':
      'O local destinado ao decaimento de rejeitos radioativos deve:\na) ser localizado em área de acesso controlado;\nb) ser sinalizado;\nc) possuir blindagem adequada;\nd) ser constituído de compartimentos que possibilitem a segregação dos rejeitos por grupo de radionuclídeos com meia-vida física próxima e por estado físico.',
  '32.4.13.7':
      'O quarto destinado à internação de paciente, para administração de radiofármacos, deve possuir:\na) blindagem;\nb) paredes e pisos com cantos arredondados, revestidos de materiais impermeáveis, que permitam sua descontaminação;\nc) sanitário privativo;\nd) biombo blindado junto ao leito;\ne) sinalização externa da presença de radiação ionizante;\nf) acesso controlado.',
  '32.4.14.1':
      'Os Serviços de Radioterapia devem adotar, no mínimo, os seguintes dispositivos de segurança:\na) salas de tratamento possuindo portas com sistema de intertravamento, que previnam o acesso indevido de pessoas durante a operação do equipamento;\nb) indicadores luminosos de equipamento em operação, localizados na sala de tratamento e em seu acesso externo, em posição visível.',
  '32.4.15.1':
      'É obrigatório manter no local de trabalho e à disposição da inspeção do trabalho o Alvará de Funcionamento vigente concedido pela autoridade sanitária local e o Programa de Garantia da Qualidade.',
  '32.4.15.3':
      'A sala de raios X deve dispor de:\na) sinalização visível na face exterior das portas de acesso, contendo o símbolo internacional de radiação ionizante, acompanhado das inscrições: "raios X, entrada restrita" ou "raios X, entrada proibida a pessoas não autorizadas";\nb) sinalização luminosa vermelha acima da face externa da porta de acesso, acompanhada do seguinte aviso de advertência: "Quando a luz vermelha estiver acesa, a entrada é proibida". A sinalização luminosa deve ser acionada durante os procedimentos radiológicos.',
  '32.4.15.6':
      'Os equipamentos móveis devem ter um cabo disparador com um comprimento mínimo de 2 metros.',
  '32.4.15.8':
      'Os equipamentos de fluoroscopia devem possuir:\na) sistema de intensificação de imagem com monitor de vídeo acoplado;\nb) cortina ou saiote plumbífero inferior e lateral para proteção do operador contra radiação espalhada;\nc) sistema para garantir que o feixe de radiação seja completamente restrito à área do receptor de imagem;\nd) sistema de alarme indicador de um determinado nível de dose ou exposição.',

  // ── 32.5 Resíduos ─────────────────────────────────────────────────────
  '32.5.2':
      'Os sacos plásticos utilizados no acondicionamento dos resíduos de saúde devem atender ao disposto na NBR 9191 e ainda ser:\na) preenchidos até 2/3 de sua capacidade;\nb) fechados de tal forma que não se permita o seu derramamento, mesmo que virados com a abertura para baixo;\nc) retirados imediatamente do local de geração após o preenchimento e fechamento;\nd) mantidos íntegros até o tratamento ou a disposição final do resíduo.',
  '32.5.3':
      'A segregação dos resíduos deve ser realizada no local onde são gerados, devendo ser observado que:\na) sejam utilizados recipientes que atendam as normas da ABNT, em número suficiente para o armazenamento;\nb) os recipientes estejam localizados próximos da fonte geradora;\nc) os recipientes sejam constituídos de material lavável, resistente à punctura, ruptura e vazamento, com tampa provida de sistema de abertura sem contato manual, com cantos arredondados e que sejam resistentes ao tombamento;\nd) os recipientes sejam identificados e sinalizados segundo as normas da ABNT.',
  '32.5.3.2':
      'Para os recipientes destinados a coleta de material perfurocortante, o limite máximo de enchimento deve estar localizado 5 cm abaixo do bocal.',
  '32.5.3.2.1':
      'O recipiente para acondicionamento dos perfurocortantes deve ser mantido em suporte exclusivo e em altura que permita a visualização da abertura para descarte.',
  '32.5.4':
      'O transporte manual do recipiente de segregação deve ser realizado de forma que não exista o contato do mesmo com outras partes do corpo, sendo vedado o arrasto.',
  '32.5.6':
      'A sala de armazenamento temporário dos recipientes de transporte deve atender, no mínimo, às seguintes características:\nI. ser dotada de:\na) pisos e paredes laváveis;\nb) ralo sifonado;\nc) ponto de água;\nd) ponto de luz;\ne) ventilação adequada;\nf) abertura dimensionada de forma a permitir a entrada dos recipientes de transporte.\nII. ser mantida limpa e com controle de vetores;\nIII. conter somente os recipientes de coleta, armazenamento ou transporte;\nIV. ser utilizada apenas para os fins a que se destina;\nV. estar devidamente sinalizada e identificada.',
  '32.5.7':
      'O transporte dos resíduos para a área de armazenamento externo deve atender aos seguintes requisitos:\na) ser feito através de carros constituídos de material rígido, lavável, impermeável, provido de tampo articulado ao próprio corpo do equipamento e cantos arredondados;\nb) ser realizado em sentido único com roteiro definido em horários não coincidentes com a distribuição de roupas, alimentos e medicamentos, períodos de visita ou de maior fluxo de pessoas.',
  '32.5.8.1':
      'O local, além de atender às características descritas no item 32.5.6, deve ser dimensionado de forma a permitir a separação dos recipientes conforme o tipo de resíduo.',

  // ── 32.6 Conforto por Ocasião das Refeições ───────────────────────────
  '32.6.2':
      'Os estabelecimentos com até 300 trabalhadores devem ser dotados de locais para refeição, que atendam aos seguintes requisitos mínimos:\na) localização fora da área do posto de trabalho;\nb) piso lavável;\nc) limpeza, arejamento e boa iluminação;\nd) mesas e assentos dimensionados de acordo com o número de trabalhadores por intervalo de descanso e refeição;\ne) lavatórios instalados nas proximidades ou no próprio local;\nf) fornecimento de água potável;\ng) possuir equipamento apropriado e seguro para aquecimento de refeições.',
  '32.6.3':
      'Os lavatórios para higiene das mãos devem ser providos de papel toalha, sabonete líquido e lixeira com tampa, de acionamento por pedal.',

  // ── 32.7 Lavanderias ──────────────────────────────────────────────────
  '32.7.1':
      'A lavanderia deve possuir duas áreas distintas, sendo uma considerada suja e outra limpa, devendo ocorrer na primeira o recebimento, classificação, pesagem e lavagem de roupas, e na segunda a manipulação das roupas lavadas.',
  '32.7.2':
      'Independente do porte da lavanderia, as máquinas de lavar devem ser de porta dupla ou de barreira, em que a roupa utilizada é inserida pela porta situada na área suja, por um operador e, após lavada, retirada na área limpa, por outro operador.',
  '32.7.2.1':
      'A comunicação entre as duas áreas somente é permitida por meio de visores ou intercomunicadores.',
  '32.7.3':
      'A calandra deve ter:\na) termômetro para cada câmara de aquecimento, indicando a temperatura das calhas ou do cilindro aquecido;\nb) termostato;\nc) dispositivo de proteção que impeça a inserção de segmentos corporais dos trabalhadores junto aos cilindros ou partes móveis da máquina.',
  '32.7.4':
      'As máquinas de lavar, centrífugas e secadoras devem ser dotadas de dispositivos eletromecânicos que interrompam seu funcionamento quando da abertura de seus compartimentos.',

  // ── 32.8 Limpeza e Conservação ────────────────────────────────────────
  '32.8.1.1':
      'A comprovação da capacitação deve ser mantida no local de trabalho, à disposição da inspeção do trabalho.',
  '32.8.2':
      'Para as atividades de limpeza e conservação, cabe ao empregador, no mínimo:\na) providenciar carro funcional destinado à guarda e transporte dos materiais e produtos indispensáveis à realização das atividades;\nb) providenciar materiais e utensílios de limpeza que preservem a integridade física do trabalhador;\nc) proibir a varrição seca nas áreas internas;\nd) proibir o uso de adornos.',
  '32.8.3':
      'As empresas de limpeza e conservação que atuam nos serviços de saúde devem cumprir, no mínimo, o disposto nos itens 32.8.1 e 32.8.2.',

  // ── 32.9 Manutenção de Máquinas e Equipamentos ────────────────────────
  '32.9.1':
      'Os trabalhadores que realizam a manutenção, além do treinamento específico para sua atividade, devem também ser submetidos a capacitação inicial e de forma continuada, com o objetivo de mantê-los familiarizados com os princípios de:\na) higiene pessoal;\nb) riscos biológico (precauções universais), físico e químico;\nc) sinalização;\nd) rotulagem preventiva;\ne) tipos de EPC e EPI, acessibilidade e seu uso correto.',
  '32.9.2':
      'Todo equipamento deve ser submetido à prévia descontaminação para realização de manutenção.',
  '32.9.2.1':
      'Na manutenção dos equipamentos, quando a descontinuidade de uso acarrete risco à vida do paciente, devem ser adotados procedimentos de segurança visando a preservação da saúde do trabalhador.',
  '32.9.3':
      'As máquinas, equipamentos e ferramentas, inclusive aquelas utilizadas pelas equipes de manutenção, devem ser submetidos à inspeção prévia e às manutenções preventivas de acordo com as instruções dos fabricantes, com a norma técnica oficial e legislação vigentes.',
  '32.9.3.1':
      'A inspeção e a manutenção devem ser registradas e estar disponíveis aos trabalhadores envolvidos e à fiscalização do trabalho.',
  '32.9.3.3':
      'O empregador deve estabelecer um cronograma de manutenção preventiva do sistema de abastecimento de gases e das capelas, devendo manter um registro individual da mesma, assinado pelo profissional que a realizou.',
  '32.9.4':
      'Os equipamentos e meios mecânicos utilizados para transporte devem ser submetidos periodicamente à manutenção, de forma a conservar os sistemas de rodízio em perfeito estado de funcionamento.',
  '32.9.5':
      'Os dispositivos de ajuste dos leitos devem ser submetidos à manutenção preventiva, assegurando a lubrificação permanente, de forma a garantir sua operação sem sobrecarga para os trabalhadores.',
  '32.9.6':
      'Os sistemas de climatização devem ser submetidos a procedimentos de manutenção preventiva e corretiva para preservação da integridade e eficiência de todos os seus componentes.',

  // ── 32.10 Disposições Gerais ──────────────────────────────────────────
  '32.10.1':
      'Os serviços de saúde devem:\na) atender as condições de conforto relativas aos níveis de ruído previstas na NB 95 da ABNT;\nb) atender as condições de iluminação conforme NB 57 da ABNT;\nc) atender as condições de conforto térmico previstas na RDC 50/02 da ANVISA;\nd) manter os ambientes de trabalho em condições de limpeza e conservação.',
  '32.10.3':
      'Antes da utilização de qualquer equipamento, os operadores devem ser capacitados quanto ao modo de operação e seus riscos.',
  '32.10.4':
      'Os manuais do fabricante de todos os equipamentos e máquinas, impressos em língua portuguesa, devem estar disponíveis aos trabalhadores envolvidos.',
  '32.10.5':
      'É vedada a utilização de material médico-hospitalar em desacordo com as recomendações de uso e especificações técnicas descritas em seu manual ou em sua embalagem.',
  '32.10.6':
      'Em todo serviço de saúde deve existir um programa de controle de animais sinantrópicos, o qual deve ser comprovado sempre que exigido pela inspeção do trabalho.',
  '32.10.7':
      'As cozinhas devem ser dotadas de sistemas de exaustão e outros equipamentos que reduzam a dispersão de gorduras e vapores, conforme estabelecido na NBR 14518.',
  '32.10.9':
      'Em todos os postos de trabalho devem ser previstos dispositivos seguros e com estabilidade, que permitam aos trabalhadores acessar locais altos sem esforço adicional.',
  '32.10.10':
      'Nos procedimentos de movimentação e transporte de pacientes deve ser privilegiado o uso de dispositivos que minimizem o esforço realizado pelos trabalhadores.',
  '32.10.13':
      'O ambiente onde são realizados procedimentos que provoquem odores fétidos deve ser provido de sistema de exaustão ou outro dispositivo que os minimizem.',
  '32.10.14': 'É vedado aos trabalhadores pipetar com a boca.',
  '32.10.15':
      'Todos os lavatórios e pias devem:\na) possuir torneiras ou comandos que dispensem o contato das mãos quando do fechamento da água;\nb) ser providos de sabão líquido e toalhas descartáveis para secagem das mãos.',

  // ── Anexo III — Plano de Prevenção de Riscos de Acidentes com
  //    Materiais Perfurocortantes ─────────────────────────────────────────
  'Anexo III item 3.3':
      'A Comissão Gestora deve elaborar e implantar procedimentos de registro e investigação de acidentes e situações de risco envolvendo materiais perfurocortantes.',
  'Anexo III item 5.1':
      'A adoção das medidas de controle deve obedecer à seguinte hierarquia:\na) substituir o uso de agulhas e outros perfurocortantes quando for tecnicamente possível;\nb) adotar controles de engenharia no ambiente (por exemplo, coletores de descarte);\nc) adotar o uso de material perfurocortante com dispositivo de segurança, quando existente, disponível e tecnicamente possível; e\nd) mudanças na organização e nas práticas de trabalho.',
  'Anexo III item 7.2':
      'A capacitação deve ser comprovada por meio de documentos que informem a data, o horário, a carga horária, o conteúdo ministrado, o nome e a formação ou capacitação profissional do instrutor e dos trabalhadores envolvidos.',
  'Anexo III item 8.3':
      'Este cronograma e a comprovação da implantação devem estar disponíveis para a Fiscalização do Ministério do Trabalho e Emprego e para os trabalhadores ou seus representantes.',
};
