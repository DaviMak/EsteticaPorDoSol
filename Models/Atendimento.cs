using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Atendimento
    {
        [Key]
        public int idAtendimento { get; set; }
        public required DateTime dtDataHoraAtendimento { get; set; }
        public int idCliente { get; set; }
        public Cliente Cliente { get; set; } = null!;
    }
}
