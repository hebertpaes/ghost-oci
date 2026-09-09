/**
 * PESQUISAS ELEITORAIS 2026 — CADASTRO EDITORIAL (Hoje MT)
 * =========================================================
 * REGRAS DE PUBLICAÇÃO (aplicadas automaticamente pelo painel):
 *  1. Só são exibidas pesquisas COM número de registro no TSE (PesqEle).
 *     Sem "registroTSE" preenchido, a pesquisa NÃO aparece no site.
 *  2. Escopo editorial: apenas BRASIL (uf: "br") e MATO GROSSO (uf: "mt").
 *     Pesquisa de outro estado só aparece se "extraordinaria: true" e com a
 *     justificativa em "notaExtraordinaria".
 *  3. O rodapé legal (Lei 9.504/97, art. 33) é montado automaticamente com:
 *     registro, contratante, instituto, período, entrevistados, margem e confiança.
 *     Preencha TODOS os campos.
 *
 * COMO CADASTRAR: copie o modelo abaixo para dentro do array PESQUISAS_2026,
 * preencha com os dados exatamente como constam no registro do TSE
 * (consulta pública: https://apps.tse.jus.br/pesqele-consulta/) e na
 * divulgação oficial do instituto. Depois reenvie o tema (ou o arquivo).
 *
 * MODELO (copie e cole):
 * {
 *   id: "mt-gov-institutoX-set26",
 *   registroTSE: "MT-00000/2026",          // nº do registro no TSE (obrigatório)
 *   uf: "mt",                               // "br" | "mt" | outra UF (exige extraordinaria)
 *   cargo: "Governador de Mato Grosso",     // texto livre exibido no título
 *   instituto: "Instituto X",
 *   contratante: "Portal Hoje MT",
 *   periodo: "10 a 14/09/2026",             // período de campo
 *   entrevistados: 1500,
 *   margem: "3",                            // margem de erro em pontos percentuais
 *   confianca: "95",                        // nível de confiança (%)
 *   dataDivulgacao: "16/09/2026",
 *   fonteUrl: "",                           // link da divulgação oficial (opcional)
 *   extraordinaria: false,                  // true só para UF fora de br/mt
 *   notaExtraordinaria: "",                 // por que está sendo divulgada (se extraordinária)
 *   cenarios: [
 *     {
 *       titulo: "Intenção de voto — estimulada",
 *       resultados: [
 *         { nome: "Candidato(a) A", pct: 34.0 },
 *         { nome: "Candidato(a) B", pct: 28.0 },
 *         { nome: "Brancos/Nulos", pct: 22.0 },
 *         { nome: "Não sabe / Não respondeu", pct: 16.0 }
 *       ]
 *     }
 *   ]
 * }
 */

window.PESQUISAS_2026 = [
  // Cadastre as pesquisas aqui (mais recente primeiro).
];
