using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace EsteticaPorDoSol.Migrations
{
    /// <inheritdoc />
    public partial class AdicionarCamposAtendimento : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_tbAtendimentos_tbClientes_ClienteidCliente",
                table: "tbAtendimentos");

            migrationBuilder.RenameColumn(
                name: "ClienteidCliente",
                table: "tbAtendimentos",
                newName: "idVeiculo");

            migrationBuilder.RenameIndex(
                name: "IX_tbAtendimentos_ClienteidCliente",
                table: "tbAtendimentos",
                newName: "IX_tbAtendimentos_idVeiculo");

            migrationBuilder.AddColumn<string>(
                name: "dsStatus",
                table: "tbAtendimentos",
                type: "longtext",
                nullable: false)
                .Annotation("MySql:CharSet", "utf8mb4");

            migrationBuilder.AddColumn<DateTime>(
                name: "dtDataHoraSaida",
                table: "tbAtendimentos",
                type: "datetime(6)",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "vlTotal",
                table: "tbAtendimentos",
                type: "decimal(65,30)",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.CreateIndex(
                name: "IX_tbAtendimentos_idCliente",
                table: "tbAtendimentos",
                column: "idCliente");

            migrationBuilder.AddForeignKey(
                name: "FK_tbAtendimentos_tbClientes_idCliente",
                table: "tbAtendimentos",
                column: "idCliente",
                principalTable: "tbClientes",
                principalColumn: "idCliente",
                onDelete: ReferentialAction.Cascade);

            migrationBuilder.AddForeignKey(
                name: "FK_tbAtendimentos_tbVeiculos_idVeiculo",
                table: "tbAtendimentos",
                column: "idVeiculo",
                principalTable: "tbVeiculos",
                principalColumn: "idVeiculo",
                onDelete: ReferentialAction.Cascade);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_tbAtendimentos_tbClientes_idCliente",
                table: "tbAtendimentos");

            migrationBuilder.DropForeignKey(
                name: "FK_tbAtendimentos_tbVeiculos_idVeiculo",
                table: "tbAtendimentos");

            migrationBuilder.DropIndex(
                name: "IX_tbAtendimentos_idCliente",
                table: "tbAtendimentos");

            migrationBuilder.DropColumn(
                name: "dsStatus",
                table: "tbAtendimentos");

            migrationBuilder.DropColumn(
                name: "dtDataHoraSaida",
                table: "tbAtendimentos");

            migrationBuilder.DropColumn(
                name: "vlTotal",
                table: "tbAtendimentos");

            migrationBuilder.RenameColumn(
                name: "idVeiculo",
                table: "tbAtendimentos",
                newName: "ClienteidCliente");

            migrationBuilder.RenameIndex(
                name: "IX_tbAtendimentos_idVeiculo",
                table: "tbAtendimentos",
                newName: "IX_tbAtendimentos_ClienteidCliente");

            migrationBuilder.AddForeignKey(
                name: "FK_tbAtendimentos_tbClientes_ClienteidCliente",
                table: "tbAtendimentos",
                column: "ClienteidCliente",
                principalTable: "tbClientes",
                principalColumn: "idCliente",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
