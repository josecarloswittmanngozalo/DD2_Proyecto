-- Fichero gen_SCL.vhd
-- Modelo VHDL 2002 de un circuito que genera el reloj (SPC)
-- para una interfaz FAST I2C
-- El reloj del circuito es de 50 MHz (Tclk = 20 ns)

-- Especificacion funcional y detalles de la implementacion:

-- 1.- Salida SPC y entrada ena_SPC
-- Especificacion: El modulo genera la se?al de reloj en el puerto de salida SPC mientras la entrada 
-- de habilitacion ena_SPC permanece activa a nivel alto; cuando dicha entrada se desactiva la salida SPC 
-- se mantiene continuamente a nivel alto. 

-- Detalles de implementacion: el modulo arranca la generacion de SPC manteniendo
-- el nivel alto, desde la activacion de ena_SPC, durante un tiempo igual al elegido para satisfacer
-- la especificacion del parametro t_HIGHmin del bus I2C en modo fast, dado que se supone que la activacion
-- de ena_SPC ocurre en el ciclo de reloj en que se produce la condicion de START (puesta a 0 de la se?al
-- SDA con SPC a nivel alto), y dicha condicion debe cumplir un tiempo de set-up respecto al primer flanco
-- de bajada de SPC (parametro tHD_STA) cuyo valor minimo coincide con el de t_HIGHmin. El valor elegido
-- como frecuencia del reloj SPC es de 400 KHz, que es el maximo especificado (f_SCLmax) para la version
-- FAST de I2C. La salida SPC debe tener direccionalidad inout por materializarse como una salida en colector abierto
-- que emplea un buffer three-state. La entrada ena_SPC debe desactivarse con la deteccion del ultimo flanco
-- de SPC de una transaccion.

-- 2.- Salidas que definen el cumplimiento de especificaciones de tiempos caracteristicos del bus I2C para
--     operaciones de otros m?dulos de la interfaz:
--
--     a.- ena_SDO: es una salida que se pone a nivel alto durante un ciclo de reloj y es empleada como
--         habilitacion de desplazamiento por el registro que en las operaciones de escritura controla la linea
--         SDA.
--
--         Detalles de implementacion: SDA debe permanecer estable mientras SPC est? a nivel alto y debe cumplir 
--         un tiempo de set-up (parametro tsu-DAT) relativo al flanco de subida de SPC y un tiempo de hold
--         (parametro tHD-DAT) relativo al flanco de bajada de SPC. Ambos tiempos deben ampliarse por efecto de
--         la especificacion de tiempos maximos de subida y bajada en los flancos de SPC y SDA derivados de la carga
--         capacitiva en la linea de reloj y de datos(tRmax y tFmax). La salida ena_SDO se activa tomando como 
--         referencia el cumplimiento del tiempo de hold y el tiempo maximo de bajada de SPC (tF), ya que de este modo 
--         se cumple sobradamente la especificacion derivada de la suma del tiempo de set-up del dato y el tiempo maximo
--         de subida del flanco de SDA (o, empleando el parametro tvd-datmax, se cumple de sobra).
--          
--     b.- ena_SDI: es una salida que se activa a nivel alto durante el ciclo de reloj coincidiendo con el instante 
--         central del estado alto de SPC. Habilita al registro de desplazamiento de lectura de SDA para que capture el valor
--         de dicha linea, correspondiente a un bit leido o al ACK.
--
--     c.- ena_up_CS: es una salida que se activa a nivel alto durante un ciclo de reloj; indica al modulo de control
--         que ya puede generarse la segnalizacion de la condici?n de STOP (flanco de subida de SDA con SPC a nivel alto).
--
--         Detalles de implementacion: La condicion de STOP debe producirse cumpliendo una especificacion de tiempo(tsu_STO)
--         relativa al flanco de subida en que el reloj SPC pasa a reposo (nivel alto) al final de una transaccion. ena_up_CS
--         se activa cumpliendo este tiempo tras el flanco de subida de SPC. 
--
--     d.- ena_down_CS: es una salida que se activa a nivel alto durante un ciclo de reloj cuando, tras una condicion de STOP,
--         la interfaz est? preparada para iniciar una nueva comunicacion 
--
--         Detalles de implementacion: el tiempo minimo que debe transcurrir entre la ocurrencia de un STOP y un subsiguiente 
--         START viene dado por el parametro t_BUFFER, cuyo valor  minimo se toma como referencia para, tras un STOP, activar la
--         salida ena_down_CS, que es utilizada por el control de la interfaz para segnalar el final de una operacion y la 
--         disponibilidad para realizar una nueva transferencia.
--
-- 3.- Salida SPC_up: salida que se activa en los flancos de subida de SPC: Su activacion solo resulta relevante en el ultimo flanco
--     de SPC.  
--
--     Detalles de implementacion: permite sincronizar la adecuada desactivacion de ena_SPC. 

--    Designer: DTE
--    Versi?n: 1.0
--    Fecha: 21-11-2016

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity gen_SCL is
port(clk:           in     std_logic;
     nRst:          in     std_logic;
     ena_SPC:       in     std_logic; 
     ena_SDO:       buffer std_logic;  -- Habilitacion de desplazamiento del registro de salida SDA
     ena_SDI:       buffer std_logic;  -- Habilitacion de desplazamiento del registro de entrada SDA
     ena_up_CS:     buffer std_logic;  -- Habilitacion de la condici?n de stop
     ena_down_CS:   buffer std_logic;  -- Indicacion de disponibilidad para nuevas transferencias
     SPC_up:        buffer std_logic;  -- Salida que se activa en los flancos de subida de SPC
     SPC:           inout  std_logic   -- Reloj I2C generado
    );
end entity;

architecture rtl of gen_SCL is
  -- Constantes correspondientes a las especificaciones de tiempo I2C en modo FAST

  constant SPI_T_SPC:        natural := 20; 
  constant SPI_T_SPC_L:      natural := 10;
  constant SPI_T_SPC_H:      natural := 10;

  constant SPI_t_su_CS:      natural := 1;
  constant SPI_t_hd_CS:      natural := 4;
  
  constant SPI_t_hd_SDI:     natural := 4;
  constant SPI_t_su_SDI:     natural := 1;

  constant SPI_t_v_SDO:      natural := 10;
  constant SPI_t_hd_SDO:     natural := 1;
  constant SPI_t_dis_SDO:    natural := 10;  

  -- Instante de muestreo de SDA (no es un parametro I2C)
  -- constant I2C_FAST_t_sample:     natural := SPI_T_SPC_H/2 + 1; -- Se muestrea SDA en el centro del pulso
  constant I2C_FAST_t_sample:     natural := SPI_T_SPC_H/2 ; --ya no es impar

  -- Cuenta para generacion de SPC y salidas
  signal cnt_SPC:           std_logic_vector(4 downto 0); 

  -- Segnales internas para el control del buffer three-state
  signal n_ctrl_SPC: std_logic;
  signal SCL_sincronizada: std_logic;

  -- Segnal interna para evitar la generacion de ena_SDI en el arranque
  signal start: std_logic;

begin
  -- Sincronizacion
  process(clk, nRst)
  begin
    if nRst = '0' then
      SCL_sincronizada<='1';
    elsif clk'event and clk = '1' then
      SCL_sincronizada<=n_ctrl_SPC;		-- flip-flop de sincronizaci?n
    end if;
  end process;
  
  
  -- Generacion de SPC
  process(clk, nRst)
  begin
    if nRst = '0' then
      cnt_SPC <= (0 => '1', others => '0');
      start <= '0';

    elsif clk'event and clk = '1' then
	 -- SCL_sincronizada<=n_ctrl_SPC;--hacer pasar la salida por un flipflop para sincronizarla
      if ena_SPC = '1' then                             -- Si ena_SPC, cuenta hasta SPI_T_SPC 
        if cnt_SPC < SPI_T_SPC then
          cnt_SPC <= cnt_SPC + 1;
        else
          cnt_SPC <= (0 => '1', others => '0'); 
          start <= '1';                                 -- Se pone a 1 al principio del nivel alto del primer pulso de SPC
        end if;
      elsif ena_down_CS /= '1' and cnt_SPC /= 1 then    -- Si no ena_SPC, cuenta hasta generacion de ena_start
        cnt_SPC <= cnt_SPC + 1;                         -- y se para preparando la cuenta para la proxima habilitacion
        start <= '0';                                   -- Se pone a 0 cuando ena_SPC se desactiva
      else
        cnt_SPC <= (0 => '1', others => '0');         
        start <= '0';
      end if;
    end if;
  end process;

  -- Generacion de las salidas
                                
  ena_SDO <= ena_SPC when cnt_SPC = (SPI_T_SPC_H + SPI_t_hd_SDI) else                   -- desplaza bit hacia SDA
                 '0';

  ena_SDI <= ena_SPC and start when cnt_SPC = I2C_FAST_t_sample else                    -- captura bit de SDA
                '0'; 

  ena_up_CS <= not ena_SPC when cnt_SPC = SPI_t_su_CS else                              -- habilita stop 
                  '0';

  ena_down_CS <= not ena_SPC when cnt_SPC = (SPI_t_su_CS + I2C_FAST_t_BUF) else         -- habilita start
                   '0';
 
  SPC_up <= start when cnt_SPC = 1                                                      -- flanco de subida de SPC
            else '0';

  -- ********************* Generacion de SPC con salida en colector (drenador abierto) ************************
  
  n_ctrl_SPC <= '1' when cnt_SPC < SPI_T_SPC_H else                                  -- reloj i2c
                '1' when cnt_SPC = SPI_T_SPC else				     --adelanta todo 1, pq asi luego se compensa al haber metido un flip flop
				not ena_SPC;  
	 
  SPC <= SCL_sincronizada when SCL_sincronizada = '0' else    --ahora salida ya pasada por el flipflop -- Modelo de la salida SPC en colector abierto
         'Z';

  --***********************************************************************************************************
end rtl;
