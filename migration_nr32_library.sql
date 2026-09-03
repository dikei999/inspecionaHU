-- ============================================================
-- InspecionaHU — Biblioteca NR-32 (templates globais por setor)
-- Execute manualmente no SQL Editor do Supabase, DEPOIS de
-- migration_demo_rpcs.sql e migration_seed_fix.sql.
--
-- Fonte do conteúdo: docs/BIBLIOTECA_NR32.md (aprovada pelo
-- orientador). Toda referência existe literalmente em
-- docs/nr32_texto.md (extraído de docs/nr32.pdf).
--
-- A função seed_nr32_library():
--   (A) cria 1 checklist_template GLOBAL por tipo de setor da
--       Parte B da biblioteca (11 templates), com os itens da
--       Parte A (description, nr32_reference, criticality,
--       requires_photo idênticos ao markdown). Idempotente:
--       checa existência por título antes de inserir; rodar
--       duas vezes não duplica nada.
--   (B) corrige os dados demo JÁ GRAVADOS no banco:
--       - desativa (status='inactive', nunca DELETE) os
--         checklist_items de NR-23 ("Extintor…" e "Rota de
--         fuga…") no hospital HU-DEMO;
--       - preenche nr32_reference/criticality/requires_photo
--         dos itens demo remanescentes, casando por description
--         exata ("Sinalização de risco biológico visível" fica
--         sem referência: não há cláusula literal na NR-32);
--       - em checklist_template_items (tabela SEM coluna
--         status), os 2 itens de NR-23 do "Template NR-32 Demo"
--         são SUBSTITUÍDOS in-place por itens válidos da
--         biblioteca (UPDATE, preservando id/order_index e a
--         integridade referencial — nenhum DELETE).
--   Retorna JSON com todas as contagens.
--
-- Chamada: SELECT seed_nr32_library();
--   - No SQL Editor (postgres) get_my_role() é NULL e a checagem
--     não bloqueia (mesmo comportamento de seed_demo_data()).
--   - Via app, apenas Super Admin autenticado consegue executar.
-- ============================================================

DROP FUNCTION IF EXISTS seed_nr32_library();

CREATE OR REPLACE FUNCTION seed_nr32_library()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_super_admin UUID;
  v_hospital_demo UUID;
  v_template_id UUID;
  v_tpl RECORD;
  v_rows INT;

  v_templates_criados INT := 0;
  v_itens_criados INT := 0;
  v_demo_itens_desativados INT := 0;
  v_demo_itens_atualizados INT := 0;
  v_demo_tpl_itens_substituidos INT := 0;
  v_demo_tpl_itens_atualizados INT := 0;
BEGIN
  IF get_my_role() != 'super_admin' THEN
    RAISE EXCEPTION 'Apenas Super Admin pode carregar a biblioteca NR-32';
  END IF;

  SELECT id INTO v_super_admin
    FROM profiles WHERE role = 'super_admin'
    ORDER BY created_at LIMIT 1;
  IF v_super_admin IS NULL THEN
    RAISE EXCEPTION 'Nenhum perfil super_admin encontrado.';
  END IF;

  -- ══════════════════════════════════════════════════════════
  -- Catálogo (Parte A da biblioteca) — fonte única do texto
  -- ══════════════════════════════════════════════════════════
  DROP TABLE IF EXISTS pg_temp.nr32_lib;
  CREATE TEMP TABLE nr32_lib (
    code           TEXT PRIMARY KEY,
    description    TEXT NOT NULL,
    nr32_reference TEXT NOT NULL,
    criticality    TEXT NOT NULL,
    requires_photo BOOLEAN NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO nr32_lib (code, description, nr32_reference, criticality, requires_photo) VALUES
    -- 32.2 Riscos Biológicos
    ('BIO-01', 'Lavatório exclusivo para higiene das mãos com água corrente, sabonete líquido, toalha descartável e lixeira com abertura sem contato manual', '32.2.4.3', 'normal', true),
    ('BIO-02', 'Quartos ou enfermarias de isolamento de doenças infectocontagiosas possuem lavatório em seu interior', '32.2.4.3.1', 'normal', true),
    ('BIO-03', 'Ausência de alimentos e bebidas nos postos de trabalho e de guarda de alimentos em locais não destinados a esse fim', '32.2.4.5', 'critical', true),
    ('BIO-04', 'Trabalhadores sem adornos, sem manuseio de lentes de contato e sem fumar nos postos de trabalho', '32.2.4.5', 'critical', true),
    ('BIO-05', 'Trabalhadores utilizando calçados fechados', '32.2.4.5', 'critical', true),
    ('BIO-06', 'Trabalhadores utilizando vestimenta de trabalho adequada e em condições de conforto', '32.2.4.6', 'normal', true),
    ('BIO-07', 'EPI descartáveis ou não disponíveis em número suficiente nos postos de trabalho, com fornecimento ou reposição imediata garantida', '32.2.4.7', 'normal', true),
    ('BIO-08', 'Locais apropriados para fornecimento de vestimentas limpas e para deposição das usadas', '32.2.4.6.3', 'normal', true),
    ('BIO-09', 'Comprovante de capacitação dos trabalhadores disponível no setor, com data, carga horária, conteúdo ministrado e identificação do instrutor', '32.2.4.9.2', 'normal', false),
    ('BIO-10', 'Instruções escritas, em linguagem acessível, das rotinas do local de trabalho e das medidas de prevenção disponíveis aos trabalhadores', '32.2.4.10', 'normal', false),
    ('BIO-11', 'Colchões, colchonetes e demais almofadados revestidos de material lavável e impermeável, sem furos, rasgos, sulcos ou reentrâncias', '32.2.4.13', 'normal', true),
    ('BIO-12', 'Trabalhadores do setor possuem comprovante das vacinas recebidas', '32.2.4.17.7', 'normal', false),
    -- 32.3 Riscos Químicos
    ('QUI-01', 'Rotulagem do fabricante mantida na embalagem original dos produtos químicos', '32.3.1', 'normal', true),
    ('QUI-02', 'Recipientes de produtos químicos manipulados ou fracionados identificados com etiqueta legível (nome, composição, concentração, data de envase e validade, responsável)', '32.3.2', 'normal', true),
    ('QUI-03', 'Embalagens de produtos químicos não são reutilizadas', '32.3.3', 'critical', true),
    ('QUI-04', 'Cópia da ficha descritiva dos produtos químicos de risco mantida no local onde o produto é utilizado', '32.3.4.1.2', 'normal', false),
    ('QUI-05', 'Chuveiro de emergência e lava-olhos presentes no local de manipulação ou fracionamento de produtos químicos', '32.3.7.1.3', 'normal', true),
    ('QUI-06', 'Manipulação ou fracionamento de produtos químicos realizado somente em local apropriado destinado a esse fim', '32.3.7.1.1', 'critical', true),
    ('QUI-07', 'Áreas de armazenamento de produtos químicos ventiladas e sinalizadas', '32.3.7.6', 'normal', true),
    ('QUI-08', 'Áreas de armazenamento próprias e separadas para produtos químicos incompatíveis', '32.3.7.6.1', 'normal', true),
    ('QUI-09', 'Cilindros de gases com identificação do gás e válvula de segurança, sem vazamentos', '32.3.8.2', 'critical', true),
    ('QUI-10', 'Cilindros de gases inflamáveis armazenados a no mínimo 8 metros dos oxidantes ou separados por barreira vedada e resistente ao fogo', '32.3.8.3', 'normal', true),
    ('QUI-11', 'Placas do sistema centralizado de gases medicinais fixadas em local visível, com pessoas autorizadas, procedimentos e telefone de emergência e sinalização de perigo', '32.3.8.4', 'normal', true),
    ('QUI-12', 'Quimioterápicos antineoplásicos preparados em área exclusiva e com acesso restrito aos profissionais diretamente envolvidos', '32.3.9.4.1', 'critical', true),
    ('QUI-13', 'Cabine de Segurança Biológica Classe II B2 na sala de preparo, com etiquetas visíveis das datas da última e da próxima manutenção', '32.3.9.4.5.1', 'critical', true),
    ('QUI-14', 'Kit de derramamento identificado e disponível nas áreas de preparação, armazenamento, administração e transporte de quimioterápicos', '32.3.9.4.9.3', 'critical', true),
    -- 32.4 Radiações Ionizantes
    ('RAD-01', 'Plano de Proteção Radiológica (PPR) mantido no local de trabalho e à disposição, dentro do prazo de vigência', '32.4.2', 'normal', false),
    ('RAD-02', 'Trabalhadores em áreas com fontes de radiação ionizante sob monitoração individual de dose (dosímetro em uso)', '32.4.3', 'critical', true),
    ('RAD-03', 'Áreas da instalação radiativa sinalizadas com o símbolo internacional de presença de radiação nos acessos controlados', '32.4.12', 'critical', true),
    ('RAD-04', 'Sala de manipulação e armazenamento de fontes com revestimento impermeável, bancadas lisas recobertas, pia com cuba de no mínimo 40 cm e torneiras sem controle manual', '32.4.13.2', 'normal', true),
    ('RAD-05', 'Ausência de alimentos, bebidas, cosméticos e bens pessoais nos locais onde são manipulados ou armazenados materiais radioativos ou rejeitos', '32.4.13.2.2', 'critical', true),
    ('RAD-06', 'Local de decaimento de rejeitos radioativos em área de acesso controlado, sinalizado, com blindagem adequada e compartimentos de segregação', '32.4.13.6', 'critical', true),
    ('RAD-07', 'Quarto de internação para administração de radiofármacos com blindagem, sanitário privativo, biombo blindado junto ao leito, sinalização externa e acesso controlado', '32.4.13.7', 'critical', true),
    ('RAD-08', 'Salas de tratamento de radioterapia com portas com sistema de intertravamento e indicadores luminosos de equipamento em operação (interno e externo)', '32.4.14.1', 'critical', true),
    ('RAD-09', 'Alvará de Funcionamento vigente e Programa de Garantia da Qualidade mantidos no local de trabalho (radiodiagnóstico)', '32.4.15.1', 'normal', false),
    ('RAD-10', 'Sala de raios X com sinalização nas portas de acesso (símbolo internacional e inscrição de entrada restrita) e sinalização luminosa vermelha com aviso de advertência', '32.4.15.3', 'critical', true),
    ('RAD-11', 'Equipamentos móveis de raios X com cabo disparador de comprimento mínimo de 2 metros', '32.4.15.6', 'critical', true),
    ('RAD-12', 'Equipamentos de fluoroscopia com cortina ou saiote plumbífero inferior e lateral e sistema de alarme de nível de dose', '32.4.15.8', 'critical', true),
    -- 32.5 Resíduos
    ('RES-01', 'Sacos de resíduos preenchidos até no máximo 2/3 da capacidade, fechados sem permitir derramamento e retirados imediatamente do local de geração após o fechamento', '32.5.2', 'normal', true),
    ('RES-02', 'Segregação dos resíduos realizada no local de geração, com recipientes em número suficiente e próximos da fonte geradora', '32.5.3', 'normal', true),
    ('RES-03', 'Recipientes de resíduos laváveis, resistentes, com tampa provida de abertura sem contato manual, cantos arredondados, identificados e sinalizados', '32.5.3', 'normal', true),
    ('RES-04', 'Recipientes de perfurocortantes preenchidos até no máximo 5 cm abaixo do bocal', '32.5.3.2', 'critical', true),
    ('RES-05', 'Recipiente de perfurocortantes mantido em suporte exclusivo e em altura que permita visualizar a abertura para descarte', '32.5.3.2.1', 'critical', true),
    ('RES-06', 'Transporte manual do recipiente de segregação sem contato com outras partes do corpo e sem arrasto', '32.5.4', 'critical', true),
    ('RES-07', 'Sala de armazenamento temporário com pisos e paredes laváveis, ralo sifonado, ventilação adequada, limpa, sinalizada e contendo somente recipientes de coleta/armazenamento/transporte', '32.5.6', 'normal', true),
    ('RES-08', 'Carros de transporte de resíduos de material rígido, lavável, impermeável, com tampa articulada e cantos arredondados', '32.5.7', 'normal', true),
    ('RES-09', 'Transporte de resíduos realizado em sentido único, com roteiro definido, em horários não coincidentes com distribuição de roupas, alimentos, medicamentos ou períodos de visita', '32.5.7', 'normal', false),
    ('RES-10', 'Local de armazenamento externo de resíduos dimensionado de forma a permitir a separação dos recipientes conforme o tipo de resíduo', '32.5.8.1', 'normal', true),
    -- 32.6 Conforto por Ocasião das Refeições
    ('REF-01', 'Local para refeições localizado fora da área do posto de trabalho', '32.6.2', 'normal', true),
    ('REF-02', 'Local para refeições com piso lavável', '32.6.2', 'normal', true),
    ('REF-03', 'Local para refeições limpo, arejado e com boa iluminação', '32.6.2', 'normal', true),
    ('REF-04', 'Mesas e assentos dimensionados de acordo com o número de trabalhadores por intervalo de descanso e refeição', '32.6.2', 'normal', true),
    ('REF-05', 'Lavatórios instalados nas proximidades ou no próprio local de refeições', '32.6.2', 'normal', true),
    ('REF-06', 'Fornecimento de água potável no local de refeições', '32.6.2', 'normal', true),
    ('REF-07', 'Equipamento apropriado e seguro para aquecimento de refeições', '32.6.2', 'normal', true),
    ('REF-08', 'Lavatórios para higiene das mãos providos de papel toalha, sabonete líquido e lixeira com tampa acionada por pedal', '32.6.3', 'normal', true),
    -- 32.7 Lavanderias
    ('LAV-01', 'Lavanderia com duas áreas distintas: uma suja e outra limpa', '32.7.1', 'normal', true),
    ('LAV-02', 'Recebimento, classificação, pesagem e lavagem ocorrendo na área suja; manipulação de roupas lavadas ocorrendo na área limpa', '32.7.1', 'normal', true),
    ('LAV-03', 'Máquinas de lavar de porta dupla ou de barreira', '32.7.2', 'normal', true),
    ('LAV-04', 'Roupa inserida pela porta da área suja por um operador e retirada na área limpa por outro operador', '32.7.2', 'normal', false),
    ('LAV-05', 'Comunicação entre as áreas suja e limpa realizada somente por visores ou intercomunicadores', '32.7.2.1', 'normal', true),
    ('LAV-06', 'Calandra com termômetro para cada câmara de aquecimento e termostato', '32.7.3', 'normal', true),
    ('LAV-07', 'Calandra com dispositivo de proteção que impeça a inserção de segmentos corporais junto aos cilindros ou partes móveis', '32.7.3', 'normal', true),
    ('LAV-08', 'Máquinas de lavar, centrífugas e secadoras dotadas de dispositivos eletromecânicos que interrompem o funcionamento na abertura dos compartimentos', '32.7.4', 'normal', true),
    -- 32.8 Limpeza e Conservação
    ('LIM-01', 'Comprovação da capacitação dos trabalhadores de limpeza mantida no local de trabalho', '32.8.1.1', 'normal', false),
    ('LIM-02', 'Carro funcional disponível para guarda e transporte dos materiais e produtos de limpeza', '32.8.2', 'normal', true),
    ('LIM-03', 'Materiais e utensílios de limpeza que preservam a integridade física do trabalhador', '32.8.2', 'normal', true),
    ('LIM-04', 'Ausência de varrição seca nas áreas internas', '32.8.2', 'critical', true),
    ('LIM-05', 'Trabalhadores de limpeza sem uso de adornos', '32.8.2', 'critical', true),
    ('LIM-06', 'Comprovação de capacitação dos trabalhadores de empresa terceirizada de limpeza disponível', '32.8.3', 'normal', false),
    -- 32.9 Manutenção de Máquinas e Equipamentos
    ('MAN-01', 'Equipamentos submetidos a prévia descontaminação antes da realização de manutenção', '32.9.2', 'critical', true),
    ('MAN-02', 'Registros de inspeção prévia e manutenção preventiva de máquinas, equipamentos e ferramentas disponíveis aos trabalhadores', '32.9.3.1', 'normal', false),
    ('MAN-03', 'Cronograma de manutenção preventiva do sistema de abastecimento de gases e das capelas, com registro individual assinado pelo profissional executor', '32.9.3.3', 'normal', false),
    ('MAN-04', 'Equipamentos e meios mecânicos de transporte com sistemas de rodízio em perfeito estado de funcionamento', '32.9.4', 'normal', true),
    ('MAN-05', 'Dispositivos de ajuste dos leitos com manutenção preventiva e lubrificação permanente, operando sem sobrecarga para os trabalhadores', '32.9.5', 'normal', true),
    ('MAN-06', 'Registros de manutenção preventiva e corretiva dos sistemas de climatização disponíveis', '32.9.6', 'normal', false),
    ('MAN-07', 'Comprovação de capacitação inicial e continuada dos trabalhadores de manutenção disponível', '32.9.1', 'normal', false),
    ('MAN-08', 'Procedimentos de segurança documentados para manutenção de equipamentos cuja descontinuidade de uso acarrete risco à vida do paciente', '32.9.2.1', 'normal', false),
    -- 32.10 Disposições Gerais
    ('GER-01', 'Ambientes de trabalho mantidos em condições de limpeza e conservação', '32.10.1', 'normal', true),
    ('GER-02', 'Comprovação de capacitação dos operadores quanto ao modo de operação e riscos dos equipamentos, anterior à utilização', '32.10.3', 'normal', false),
    ('GER-03', 'Manuais dos fabricantes de equipamentos e máquinas, impressos em língua portuguesa, disponíveis aos trabalhadores envolvidos', '32.10.4', 'normal', false),
    ('GER-04', 'Material médico-hospitalar utilizado de acordo com as recomendações de uso e especificações técnicas do manual ou da embalagem', '32.10.5', 'critical', true),
    ('GER-05', 'Comprovação do programa de controle de animais sinantrópicos disponível', '32.10.6', 'normal', false),
    ('GER-06', 'Cozinha dotada de sistema de exaustão e equipamentos que reduzam a dispersão de gorduras e vapores', '32.10.7', 'normal', true),
    ('GER-07', 'Dispositivos seguros e com estabilidade disponíveis para acesso a locais altos sem esforço adicional', '32.10.9', 'normal', true),
    ('GER-08', 'Dispositivos que minimizem o esforço dos trabalhadores disponíveis para movimentação e transporte de pacientes', '32.10.10', 'normal', true),
    ('GER-09', 'Ausência da prática de pipetagem com a boca', '32.10.14', 'critical', true),
    ('GER-10', 'Lavatórios e pias com torneiras ou comandos que dispensam o contato das mãos no fechamento, providos de sabão líquido e toalhas descartáveis', '32.10.15', 'normal', true),
    ('GER-11', 'Ambientes onde são realizados procedimentos com odores fétidos providos de sistema de exaustão ou dispositivo que os minimize', '32.10.13', 'normal', true),
    -- Anexo III — Perfurocortantes
    ('PFC-01', 'Ausência da prática de reencape e de desconexão manual de agulhas', '32.2.4.15', 'critical', true),
    ('PFC-02', 'Descarte de objetos perfurocortantes realizado pelo próprio trabalhador que os utilizou', '32.2.4.14', 'critical', true),
    ('PFC-03', 'Materiais perfurocortantes com dispositivo de segurança em uso, quando existente, disponível e tecnicamente possível', 'Anexo III item 5.1', 'critical', true),
    ('PFC-04', 'Coletores de descarte de perfurocortantes disponíveis nos pontos de uso (controle de engenharia)', 'Anexo III item 5.1', 'critical', true),
    ('PFC-05', 'Plano de Prevenção de Riscos de Acidentes com Materiais Perfurocortantes elaborado e disponível', '32.2.4.16', 'normal', false),
    ('PFC-06', 'Cronograma de implementação do plano de prevenção e comprovação da implantação disponíveis', 'Anexo III item 8.3', 'normal', false),
    ('PFC-07', 'Comprovação da capacitação para prevenção de acidentes com perfurocortantes, com data, carga horária, conteúdo e identificação do instrutor', 'Anexo III item 7.2', 'normal', false),
    ('PFC-08', 'Procedimentos de registro e investigação de acidentes e situações de risco com perfurocortantes implantados e documentados', 'Anexo III item 3.3', 'normal', false);

  -- ══════════════════════════════════════════════════════════
  -- Templates por setor (Parte B da biblioteca)
  -- ══════════════════════════════════════════════════════════
  DROP TABLE IF EXISTS pg_temp.nr32_tpl;
  CREATE TEMP TABLE nr32_tpl (
    ord      INT,
    title    TEXT,
    descr    TEXT,
    category TEXT,
    codes    TEXT[]
  ) ON COMMIT DROP;

  INSERT INTO nr32_tpl (ord, title, descr, category, codes) VALUES
    (1, 'Lavanderia',
     'Processamento de roupas hospitalares, do recebimento de roupa suja à expedição de roupa limpa.',
     '32.7 Lavanderias',
     ARRAY['LAV-01','LAV-02','LAV-03','LAV-04','LAV-05','LAV-06','LAV-07','LAV-08','BIO-01','BIO-05','BIO-06','BIO-07','BIO-09','QUI-01','QUI-04','RES-01','RES-03','GER-01','GER-10']),
    (2, 'Centro Cirúrgico',
     'Salas cirúrgicas e áreas de apoio, com exposição biológica direta, perfurocortantes e gases medicinais/anestésicos.',
     '32.2 Riscos Biológicos',
     ARRAY['BIO-01','BIO-03','BIO-04','BIO-05','BIO-06','BIO-07','BIO-10','QUI-09','QUI-11','PFC-01','PFC-02','PFC-03','PFC-04','RES-01','RES-04','RES-05','MAN-01','GER-01','GER-04','GER-10']),
    (3, 'CME',
     'Recepção, limpeza, desinfecção e esterilização de materiais e instrumentais.',
     '32.2 Riscos Biológicos',
     ARRAY['BIO-01','BIO-03','BIO-05','BIO-06','BIO-07','BIO-09','QUI-01','QUI-02','QUI-03','QUI-04','QUI-06','MAN-01','MAN-02','MAN-03','PFC-01','PFC-04','RES-04','GER-01','GER-04','GER-10']),
    (4, 'Enfermaria',
     'Unidades de internação com assistência direta ao paciente.',
     '32.2 Riscos Biológicos',
     ARRAY['BIO-01','BIO-02','BIO-03','BIO-04','BIO-05','BIO-06','BIO-07','BIO-10','BIO-11','PFC-01','PFC-02','PFC-04','RES-01','RES-02','RES-03','RES-04','RES-05','MAN-05','GER-01','GER-08','GER-10']),
    (5, 'Laboratório',
     'Análises clínicas e manipulação de material biológico e químico.',
     '32.2 Riscos Biológicos',
     ARRAY['BIO-01','BIO-03','BIO-04','BIO-05','BIO-06','BIO-07','BIO-09','BIO-10','QUI-01','QUI-02','QUI-03','QUI-04','QUI-05','QUI-06','QUI-07','QUI-08','PFC-01','PFC-04','RES-04','RES-05','GER-01','GER-09','GER-10']),
    (6, 'Farmácia e Quimioterapia',
     'Armazenamento, fracionamento e preparo de medicamentos, incluindo quimioterápicos antineoplásicos.',
     '32.3 Riscos Químicos',
     ARRAY['QUI-01','QUI-02','QUI-03','QUI-04','QUI-05','QUI-06','QUI-07','QUI-08','QUI-12','QUI-13','QUI-14','BIO-01','BIO-03','BIO-06','BIO-07','PFC-01','PFC-03','PFC-04','RES-04','GER-01','GER-10']),
    (7, 'Radiologia e Medicina Nuclear',
     'Serviços com radiação ionizante — radiodiagnóstico, medicina nuclear e radioterapia.',
     '32.4 Radiações Ionizantes',
     ARRAY['RAD-01','RAD-02','RAD-03','RAD-04','RAD-05','RAD-06','RAD-07','RAD-08','RAD-09','RAD-10','RAD-11','RAD-12','BIO-01','BIO-03','BIO-07','RES-01','GER-01','GER-10']),
    (8, 'Nutrição e Cozinha',
     'Preparo e distribuição de alimentos e áreas de refeição dos trabalhadores.',
     '32.6 Conforto por Ocasião das Refeições',
     ARRAY['REF-01','REF-02','REF-03','REF-04','REF-05','REF-06','REF-07','REF-08','GER-06','GER-05','GER-01','GER-07','GER-10','QUI-01','QUI-04','RES-01','RES-02','RES-03']),
    (9, 'Limpeza e Conservação',
     'Higienização dos ambientes do serviço de saúde, própria ou terceirizada.',
     '32.8 Limpeza e Conservação',
     ARRAY['LIM-01','LIM-02','LIM-03','LIM-04','LIM-05','LIM-06','BIO-05','BIO-06','BIO-07','BIO-09','QUI-01','QUI-02','QUI-04','RES-01','RES-02','RES-03','RES-06','GER-01','GER-10']),
    (10, 'Manutenção',
     'Manutenção predial e de máquinas e equipamentos do serviço de saúde.',
     '32.9 Manutenção de Máquinas e Equipamentos',
     ARRAY['MAN-01','MAN-02','MAN-03','MAN-04','MAN-05','MAN-06','MAN-07','MAN-08','BIO-06','BIO-07','BIO-09','QUI-01','QUI-04','QUI-09','QUI-10','GER-01','GER-03','GER-07']),
    (11, 'Resíduos',
     'Segregação, acondicionamento, transporte interno e armazenamento de resíduos de serviços de saúde.',
     '32.5 Resíduos',
     ARRAY['RES-01','RES-02','RES-03','RES-04','RES-05','RES-06','RES-07','RES-08','RES-09','RES-10','PFC-04','BIO-05','BIO-06','BIO-07','QUI-03','GER-01']);

  -- Sanidade: todo código citado nos templates existe no catálogo
  IF EXISTS (
    SELECT 1 FROM nr32_tpl t, unnest(t.codes) c
    WHERE NOT EXISTS (SELECT 1 FROM nr32_lib l WHERE l.code = c)
  ) THEN
    RAISE EXCEPTION 'Template cita código inexistente no catálogo NR-32';
  END IF;

  -- ── (A) Criação idempotente dos templates globais ──────────
  FOR v_tpl IN SELECT * FROM nr32_tpl ORDER BY ord LOOP
    SELECT id INTO v_template_id FROM checklist_templates
      WHERE scope = 'global' AND title = v_tpl.title;

    IF v_template_id IS NULL THEN
      INSERT INTO checklist_templates
        (hospital_id, title, description, nr32_category, scope, created_by, status)
      VALUES
        (NULL, v_tpl.title, v_tpl.descr, v_tpl.category, 'global', v_super_admin, 'active')
      RETURNING id INTO v_template_id;
      v_templates_criados := v_templates_criados + 1;

      INSERT INTO checklist_template_items
        (template_id, order_index, description, nr32_reference, criticality, requires_photo)
      SELECT v_template_id, ord.idx, lib.description, lib.nr32_reference,
             lib.criticality, lib.requires_photo
      FROM unnest(v_tpl.codes) WITH ORDINALITY AS ord(code, idx)
      JOIN nr32_lib lib ON lib.code = ord.code
      ORDER BY ord.idx;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      v_itens_criados := v_itens_criados + v_rows;
    END IF;
  END LOOP;

  -- ══════════════════════════════════════════════════════════
  -- (B) Correção dos dados demo JÁ GRAVADOS (idempotente)
  -- ══════════════════════════════════════════════════════════
  SELECT id INTO v_hospital_demo FROM hospitals WHERE sigla = 'HU-DEMO';

  IF v_hospital_demo IS NOT NULL THEN
    -- (B1) Desativa os itens de NR-23 (soft delete — inspeções já
    -- respondidas continuam íntegras: os relatórios buscam itens
    -- por id sem filtro de status).
    UPDATE checklist_items ci
    SET status = 'inactive'
    WHERE ci.status = 'active'
      AND ci.description IN
        ('Extintor de incêndio dentro da validade', 'Rota de fuga desobstruída')
      AND ci.checklist_id IN
        (SELECT id FROM checklists WHERE hospital_id = v_hospital_demo);
    GET DIAGNOSTICS v_demo_itens_desativados = ROW_COUNT;

    -- (B2) Preenche referência/criticidade/foto dos itens demo
    -- remanescentes, casando por description exata.
    -- "Sinalização de risco biológico visível" fica de fora de
    -- propósito: não há cláusula literal correspondente na NR-32.
    DROP TABLE IF EXISTS pg_temp.demo_map;
    CREATE TEMP TABLE demo_map (
      description TEXT PRIMARY KEY,
      nr32_reference TEXT,
      criticality TEXT,
      requires_photo BOOLEAN
    ) ON COMMIT DROP;
    INSERT INTO demo_map VALUES
      ('EPI disponível e em bom estado',            '32.2.4.7', 'normal',   true),
      ('Separação de roupa suja/limpa respeitada',  '32.7.1',   'normal',   true),
      ('Piso sem risco de escorregamento',          '32.10.1',  'normal',   true),
      ('Autoclave funcionando corretamente',        '32.9.3',   'critical', true),
      ('Descarte de perfurocortantes adequado',     '32.5.3.2', 'critical', true);

    UPDATE checklist_items ci
    SET nr32_reference = m.nr32_reference,
        criticality    = m.criticality,
        requires_photo = m.requires_photo
    FROM demo_map m
    WHERE ci.description = m.description
      AND ci.checklist_id IN
        (SELECT id FROM checklists WHERE hospital_id = v_hospital_demo)
      AND (ci.nr32_reference IS DISTINCT FROM m.nr32_reference
        OR ci.criticality    IS DISTINCT FROM m.criticality
        OR ci.requires_photo IS DISTINCT FROM m.requires_photo);
    GET DIAGNOSTICS v_demo_itens_atualizados = ROW_COUNT;
  END IF;

  -- (B3) "Template NR-32 Demo": checklist_template_items não tem
  -- coluna status. Estratégia: SUBSTITUIÇÃO in-place (UPDATE) dos
  -- 2 itens de NR-23 por itens válidos da biblioteca — preserva
  -- id, order_index e integridade referencial, sem DELETE.
  -- Idempotente: após a 1ª execução a description antiga não
  -- existe mais e o UPDATE afeta 0 linhas.
  UPDATE checklist_template_items ti
  SET description    = l.description,
      nr32_reference = l.nr32_reference,
      criticality    = l.criticality,
      requires_photo = l.requires_photo
  FROM (VALUES
      ('Extintor de incêndio dentro da validade', 'RES-04'),
      ('Rota de fuga desobstruída',               'BIO-01')
    ) AS sub(old_description, new_code)
  JOIN nr32_lib l ON l.code = sub.new_code
  WHERE ti.description = sub.old_description
    AND ti.template_id IN
      (SELECT id FROM checklist_templates WHERE title = 'Template NR-32 Demo');
  GET DIAGNOSTICS v_demo_tpl_itens_substituidos = ROW_COUNT;

  -- (B4) Preenche referência dos itens restantes do template demo.
  UPDATE checklist_template_items ti
  SET nr32_reference = '32.2.4.7', criticality = 'normal', requires_photo = true
  WHERE ti.description = 'EPI disponível e em bom estado'
    AND ti.template_id IN
      (SELECT id FROM checklist_templates WHERE title = 'Template NR-32 Demo')
    AND (ti.nr32_reference IS DISTINCT FROM '32.2.4.7'
      OR ti.criticality IS DISTINCT FROM 'normal'
      OR ti.requires_photo IS DISTINCT FROM true);
  GET DIAGNOSTICS v_demo_tpl_itens_atualizados = ROW_COUNT;

  RETURN json_build_object(
    'status', 'ok',
    'templates_criados', v_templates_criados,
    'itens_criados', v_itens_criados,
    'demo_itens_desativados', v_demo_itens_desativados,
    'demo_itens_atualizados', v_demo_itens_atualizados,
    'demo_template_itens_substituidos', v_demo_tpl_itens_substituidos,
    'demo_template_itens_atualizados', v_demo_tpl_itens_atualizados,
    'demo_itens_sem_referencia',
      json_build_array('Sinalização de risco biológico visível')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION seed_nr32_library() TO authenticated;
