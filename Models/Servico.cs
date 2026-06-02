using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Servico
    {
        [Key]
        public int idServico { get; set; }
        public required string dsNomeServico { get; set; }
        public required string dsDescricaoServico { get; set; }
        public decimal vlServico { get; set; }
    }
}
