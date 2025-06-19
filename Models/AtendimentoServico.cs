using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class AtendimentoServico
    {
        [Key]
        public int idAtendimentoServico { get; set; }
        public int idAtendimento { get; set; }
        public int idServico { get; set; }
        public Atendimento Atendimento { get; set; } = null!;
        public Servico Servico { get; set; } = null!;
    }
}
