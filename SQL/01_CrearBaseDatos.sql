/* ============================================================
   Proyecto : ETL de carga y validación de ventas
   Base     : ETLVentasDB
   Archivo  : 01_CrearBaseDatos.sql
   ============================================================ */

USE master;
GO


/* ============================================================
   1. CREAR BASE DE DATOS
   ============================================================ */

IF DB_ID(N'ETLVentasDB') IS NULL
BEGIN
    CREATE DATABASE ETLVentasDB;
END;
GO


USE ETLVentasDB;
GO


/* ============================================================
   2. CREAR TABLA CLIENTE
   ============================================================ */

IF OBJECT_ID(N'dbo.Cliente', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Cliente
    (
        IdCliente INT NOT NULL,
        NombreCliente NVARCHAR(150) NOT NULL,

        CONSTRAINT PK_Cliente PRIMARY KEY (IdCliente)
    );
END;
GO


/* ============================================================
   3. CREAR TABLA VENTA
   ============================================================ */

IF OBJECT_ID(N'dbo.Venta', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Venta
    (
        IdVenta INT NOT NULL,
        FechaVenta DATE NOT NULL,
        IdCliente INT NOT NULL,
        Producto NVARCHAR(150) NOT NULL,
        Cantidad INT NOT NULL,
        PrecioUnitario DECIMAL(18,2) NOT NULL,
        ImporteTotal DECIMAL(18,2) NOT NULL,
        Estado VARCHAR(20) NOT NULL,

        FechaCarga DATETIME2(0) NOT NULL CONSTRAINT DF_Venta_FechaCarga DEFAULT (SYSDATETIME()),

        CONSTRAINT PK_Venta PRIMARY KEY (IdVenta),

        CONSTRAINT FK_Venta_Cliente FOREIGN KEY (IdCliente) REFERENCES dbo.Cliente(IdCliente)
    );
END;
GO


/* ============================================================
   4. CREAR INDICE PARA IdCliente
   ============================================================ */

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_Venta_IdCliente' AND object_id = OBJECT_ID(N'dbo.Venta')
)
BEGIN
    CREATE INDEX IX_Venta_IdCliente ON dbo.Venta(IdCliente);
END;
GO


/* ============================================================
   5. INSERTAR CLIENTES DE PRUEBA
   ============================================================ */

INSERT INTO dbo.Cliente (IdCliente, NombreCliente)
VALUES
    (1, N'Carlos Pérez'),
    (2, N'Ana Torres'),
    (3, N'Luis Ramos'),
    (4, N'María Flores'),
    (5, N'Pedro Sánchez');
GO


/* ============================================================
   6. COMPROBACIONES CON SELECTS
   ============================================================ */

SELECT
    IdCliente,
    NombreCliente
FROM dbo.Cliente
ORDER BY IdCliente;
GO


SELECT
    IdVenta,
    FechaVenta,
    IdCliente,
    Producto,
    Cantidad,
    PrecioUnitario,
    ImporteTotal,
    Estado,
    FechaCarga
FROM dbo.Venta
ORDER BY IdVenta;
GO