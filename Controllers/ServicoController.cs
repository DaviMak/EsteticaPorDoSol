using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc;

namespace EsteticaPorDoSol.Controllers
{
    public class ServicoController : Controller
    {
        private readonly ApplicationDbContext _context;

        public ServicoController(ApplicationDbContext context)
        {
            _context = context;
        }
        public IActionResult ListarServico()
        {
            var listaServicos = _context.tbServicos.ToList();
            return View(listaServicos);
        }
        [HttpGet]
        public IActionResult CadastrarServico()
        {
            return View();
        }

        public IActionResult ExcluirServico(int id)
        {
            var servico = _context.tbServicos.Find(id);
            if (servico != null)
            {
                _context.tbServicos.Remove(servico);
                _context.SaveChanges();
                ViewBag.Mensagem = "Servico excluído com sucesso!";
            }
            else
            {
                ViewBag.Mensagem = "Servico não encontrado.";
            }
            return RedirectToAction("ListarServico");
        }
        [HttpGet]
        public IActionResult EditarServico(int id)
        {
            var servico = _context.tbServicos.Find(id);
            if (servico == null)
            {
                TempData["Mensagem"] = "Servico não encontrado.";
                return RedirectToAction("ListarServico");
            }

            return View("EditarServico", servico);
        }

        [HttpPost]
        public IActionResult EditarServico(Servico servico)
        {
            try
            {
                servico.vlServico = Math.Round(servico.vlServico, 2);
                _context.tbServicos.Update(servico);
                _context.SaveChanges();
                ViewBag.Mensagem = "Servico atualizado com sucesso!";
                return RedirectToAction("ListarServico");
            }
            catch (Exception ex)
            {
                ViewBag.Mensagem = $"Erro ao atualizar servico: {ex.Message}";
                return View(servico);
            }
        }
        [HttpPost]
        public IActionResult CadastrarServico(Servico servico)
        {
            if (ModelState.IsValid)
            {
                servico.vlServico = Math.Round(servico.vlServico, 2);
                _context.tbServicos.Add(servico);
                _context.SaveChanges();
                ViewBag.Mensagem = "Servico cadastrado com sucesso!";
                return RedirectToAction("ListarServico");
            }
            ViewBag.Mensagem = "Erro ao cadastrar servico. Verifique os dados e tente novamente.";
            return View(servico);
        }


    }
}
