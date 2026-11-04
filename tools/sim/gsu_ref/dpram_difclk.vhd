library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
-- Behavioural stand-in for MiSTer's altsyncram wrapper: address registered,
-- output unregistered (one-clock read latency); port A is read-only in GSU.
entity dpram_difclk is
  generic (aw0: natural := 9; dw0: natural := 8; aw1: natural := 9; dw1: natural := 8);
  port (clock0: in std_logic; address_a: in std_logic_vector(aw0-1 downto 0);
        data_a: in std_logic_vector(dw0-1 downto 0); wren_a: in std_logic;
        q_a: out std_logic_vector(dw0-1 downto 0);
        clock1: in std_logic; address_b: in std_logic_vector(aw1-1 downto 0);
        data_b: in std_logic_vector(dw1-1 downto 0); wren_b: in std_logic;
        q_b: out std_logic_vector(dw1-1 downto 0));
end entity;
architecture rtl of dpram_difclk is
  type mem_t is array (0 to 2**aw1-1) of std_logic_vector(dw1-1 downto 0);
  signal mem: mem_t := (others => (others => '0'));
begin
  process(clock1) begin
    if rising_edge(clock1) then
      if wren_b = '1' then mem(to_integer(unsigned(address_b))) <= data_b; end if;
      q_b <= mem(to_integer(unsigned(address_b)));
    end if;
  end process;
  process(clock0) begin
    if rising_edge(clock0) then q_a <= mem(to_integer(unsigned(address_a))); end if;
  end process;
end architecture;
