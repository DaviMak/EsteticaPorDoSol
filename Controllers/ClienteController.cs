using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Mvc;

namespace EsteticaPorDoSol.Controllers
{
    public class ClienteController : Controller
    {
        private readonly ApplicationDbContext _context;

        public ClienteController(ApplicationDbContext context)
        {
            _context = context;
        }

        public IActionResult ListarCliente()
        {
            var listaClientes = _context.tbClientes.ToList();
            return View(listaClientes);
        }

        public IActionResult Excluir(int id)
        {
            var cliente = _context.tbClientes.Find(id);
            if (cliente != null)
            {
                _context.tbClientes.Remove(cliente);
                _context.SaveChanges();
                ViewBag.Mensagem = "Cliente excluído com sucesso!";
            }
            else
            {
                ViewBag.Mensagem = "Cliente não encontrado.";
            }
            return RedirectToAction("ListarCliente");
        }

        public IActionResult Editar(int id)
        { 
            var cliente = _context.tbClientes.Find(id);
            if (cliente == null)
            {
                TempData["Mensagem"] = "Cliente não encontrado.";
                return RedirectToAction("ListarCliente");
            }

            return View("EditarCliente", cliente);
        }
        [HttpPost]
        public IActionResult EditarCliente(Cliente cliente)
        {
            try
            {
                _context.tbClientes.Update(cliente);
                _context.SaveChanges();
                ViewBag.Mensagem = "Cliente atualizado com sucesso!";
                return RedirectToAction("ListarCliente");
            }
            catch (Exception ex)
            {
                ViewBag.Mensagem = $"Erro ao atualizar cliente: {ex.Message}";
                return View(cliente);
            }
        }
    }
}
