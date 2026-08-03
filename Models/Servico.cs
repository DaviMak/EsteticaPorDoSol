using System.ComponentModel.DataAnnotations;

namespace EsteticaPorDoSol.Models
{
    public class Servico
    {
        [Key]
        public int idServico { get; set; }
        [Required(ErrorMessage = "Campo obrigatório")]
        public required string dsNomeServico { get; set; }
        public required string dsDescricaoServico { get; set; }
        [DisplayFormat(DataFormatString = "{0:N2}", ApplyFormatInEditMode = true)]
        public decimal vlServico { get; set; }
        
    }
}
