using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EsteticaPorDoSol.Models
{
    public class AtendimentoServico
    {
        [Key]
        public int idAtendimentoServico { get; set; }
        public int idAtendimento { get; set; }
        public int idServico { get; set; }
        [ForeignKey("idAtendimento")]
        public Atendimento Atendimento { get; set; } = null!;
        [ForeignKey("idServico")]
        public Servico Servico { get; set; } = null!;
    }
}
