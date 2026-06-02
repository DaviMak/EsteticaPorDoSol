using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace EsteticaPorDoSol.Controllers
{
    public class VeiculoController : Controller
    {
        private readonly ApplicationDbContext _context;

        public VeiculoController(ApplicationDbContext context)
        {
            _context = context;
        }

        public IActionResult ListarVeiculo()
        {
            var listaVeiculos = _context.tbVeiculos
                .Include(v => v.Cliente)
                .ToList();
            return View(listaVeiculos);
        }

        public IActionResult Excluir(int id)
        {
            var veiculo = _context.tbVeiculos.Find(id);
            if (veiculo != null)
            {
                _context.tbVeiculos.Remove(veiculo);
                _context.SaveChanges();
                ViewBag.Mensagem = "Veículo excluído com sucesso!";
            }
            else
            {
                ViewBag.Mensagem = "Veículo não encontrado.";
            }
            return RedirectToAction("ListarVeiculo");
        }

        public IActionResult Editar(int id)
        {
            var veiculo = _context.tbVeiculos.Find(id);
            if (veiculo == null)
            {
                TempData["Mensagem"] = "Veículo não encontrado.";
                return RedirectToAction("ListarVeiculo");
            }
                ViewBag.Clientes = _context.tbClientes.ToList();
                return View("EditarVeiculo", veiculo);
        }
        [HttpPost]
        public IActionResult EditarVeiculo(Veiculo veiculo)
        {
            try
            {
                _context.tbVeiculos.Update(veiculo);
                _context.SaveChanges();
                ViewBag.Mensagem = "Veículo atualizado com sucesso!";
                return RedirectToAction("ListarVeiculo");
            }
            catch (Exception ex)
            {
                ViewBag.Mensagem = $"Erro ao atualizar veículo: {ex.Message}";
                return View("EditarVeiculo", veiculo);
            }
        }
        [HttpGet]
        public IActionResult CadastrarVeiculo()
        {
            ViewBag.Clientes = _context.tbClientes.ToList();
            return View("CadastrarVeiculo");
        }

        [HttpPost]
        public IActionResult CadastrarVeiculo(Veiculo veiculo)
        {
            //veiculo.Cliente = _context.tbClientes.Find(veiculo.idCliente);
            if (ModelState.IsValid)
            {
                _context.tbVeiculos.Add(veiculo);
                _context.SaveChanges();
                ViewBag.Mensagem = "Veículo cadastrado com sucesso!";
                return RedirectToAction("ListarVeiculo");
            }
            TempData["Mensagem"] = "Erro ao cadastrar Veículo. Verifique os dados e tente novamente.";
            ViewBag.Clientes = _context.tbClientes.ToList();

            return View("CadastrarVeiculo", veiculo);
        }
    }
}
