using System;
using System.Collections.Generic;
using EsteticaPorDoSol.Controllers;
using EsteticaPorDoSol.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ViewFeatures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace EsteticaPorDoSol.Tests
{
    public class ClienteControllerTests
    {
        private ApplicationDbContext CriarContexto()
        {
            var options = new DbContextOptionsBuilder<ApplicationDbContext>()
                .UseInMemoryDatabase(Guid.NewGuid().ToString())
                .Options;

            return new ApplicationDbContext(options);
        }

        private ClienteController CriarController(ApplicationDbContext context)
        {
            var controller = new ClienteController(context);

            var httpContext = new DefaultHttpContext();

            controller.ControllerContext = new ControllerContext
            {
                HttpContext = httpContext
            };

            controller.TempData = new TempDataDictionary(
                httpContext,
                new FakeTempDataProvider()
            );

            return controller;
        }

        [Fact]
        public void Excluir_ClienteComVeiculo_NaoDeveExcluir()
        {
            // Arrange
            using var context = CriarContexto();

            var cliente = new Cliente
            {
                idCliente = 1,
                dsNome = "João"
            };

            var veiculo = new Veiculo
            {
                idVeiculo = 1,
                dsPlaca = "ABC1234",
                dsModelo = "Gol",
                dsCor = "Branco",
                idCliente = 1
            };

            context.tbClientes.Add(cliente);
            context.tbVeiculos.Add(veiculo);
            context.SaveChanges();

            var controller = CriarController(context);

            // Act
            var resultado = controller.Excluir(1);

            // Assert
            var redirect = Assert.IsType<RedirectToActionResult>(resultado);

            Assert.Equal("ListarCliente", redirect.ActionName);

            Assert.Equal(
                "Não é possível excluir o cliente, pois ele possui veículos cadastrados.",
                controller.TempData["Mensagem"]
            );

            Assert.NotNull(context.tbClientes.Find(1));
        }

        [Fact]
        public void Excluir_ClienteSemVeiculo_DeveExcluir()
        {
            // Arrange
            using var context = CriarContexto();

            var cliente = new Cliente
            {
                idCliente = 1,
                dsNome = "João"
            };

            context.tbClientes.Add(cliente);
            context.SaveChanges();

            var controller = CriarController(context);

            // Act
            var resultado = controller.Excluir(1);

            // Assert
            var redirect = Assert.IsType<RedirectToActionResult>(resultado);

            Assert.Equal("ListarCliente", redirect.ActionName);

            Assert.Equal(
                "Cliente excluído com sucesso!",
                controller.TempData["Sucesso"]
            );

            Assert.Null(context.tbClientes.Find(1));
        }
    }

    public class FakeTempDataProvider : ITempDataProvider
    {
        private readonly Dictionary<string, object> _data = new();

        public IDictionary<string, object> LoadTempData(HttpContext context)
        {
            return _data;
        }

        public void SaveTempData(
            HttpContext context,
            IDictionary<string, object> values)
        {
            _data.Clear();

            foreach (var item in values)
            {
                _data[item.Key] = item.Value;
            }
        }
    }
}