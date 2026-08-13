using Microsoft.AspNetCore.Mvc;
using EsteticaPorDoSol.Models; // ajuste o namespace se necessário

namespace EsteticaPorDoSol.Controllers
{
    public class CadastroController : Controller
    {
        private readonly ApplicationDbContext _context;

        public CadastroController(ApplicationDbContext context)
        {
            _context = context;
        }

        public IActionResult Cadastro()
        {
            string mensagem;
            try
            {
                var existe = _context.tbClientes.Any();
                mensagem = "Conexão com o banco de dados bem-sucedida!";
            }
            catch (Exception ex)
            {
                mensagem = $"Erro ao conectar com o banco: {ex.Message}";
            }

            ViewBag.Mensagem = mensagem;
            return View();
        }

        //[HttpPost]
        //public IActionResult Cadastro(Cliente cliente)
        //{
        //    if (ModelState.IsValid)
        //    {
        //        _context.tbClientes.Add(cliente);
        //        _context.SaveChanges();
        //        ViewBag.Mensagem = "Cliente cadastrado com sucesso!";
        //        return RedirectToAction("Cadastro");
        //    }
        //    ViewBag.Mensagem = "Erro ao cadastrar cliente. Verifique os dados e tente novamente.";
        //    return View(cliente);
        //}
    }
}
