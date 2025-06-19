using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Servico
    {
        [Key]
        public int idServico { get; set; }
        public required string dsServico { get; set; }
        public required string dsDescricaoServico { get; set; }
    }
}
