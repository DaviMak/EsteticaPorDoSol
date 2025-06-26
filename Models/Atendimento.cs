using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace EsteticaPorDoSol.Models
{
    public class Atendimento
    {
        [Key]
        public int idAtendimento { get; set; }
        [Required]
        public int idCliente { get; set; }
        public required DateTime dtDataHoraAtendimento { get; set; }
        [ForeignKey("idCliente")]
        public Cliente Cliente { get; set; } = null!;
        public List<AtendimentoServico> AtendimentoServicos { get; set; } = null!;
    }
}
