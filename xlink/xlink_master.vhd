-- Author:  Andrzej Cichocki
-- Centrum Badan Kosmicznych PAN
-- ASIM MXGS Project
-- Public domain released with master thesis 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity xlink_master is
    port(
        clk             :   in std_logic;
        rstn            :   in std_logic;
        tx_go           :   in std_logic;
        tx_irq          :   out std_logic;
        tx_data         :   in std_logic_vector(23 downto 0);
        rx_data         :   out std_logic_vector(23 downto 0);
        rx_irq          :   out std_logic;
		tx_prescale     :   in std_logic_vector(15 downto 0);
        tx_busy         :   out std_logic;
        rx_error        :   out std_logic;
        strobe_in       :   in std_logic; 
        data_in         :   in std_logic;
        strobe_out      :   out std_logic;
        data_out        :   out std_logic
    );
    
end entity;

architecture prim of xlink_master is
    signal clk_rec      :   std_logic;
    signal clk_rec_buf  :   std_logic;
    signal rxdata_r    :   std_logic_vector(13 downto 0);
    signal rxdata_f    :   std_logic_vector(13 downto 1);

    type TTXState is ( stIdle, stTransmit1, stTransmit0, stStop1, stStop2, stSilent1, stSilent2, StSilent3, stIrq);
    
    type RxState_t is ( stIdle, stReceive, stError, stIrq,stResync, stSilent);
    
    type RxContext_t is record
        State       : RxState_t;
        RxData     : std_logic_vector(23 downto 0); 
        CntRst      : std_logic;
        Irq         : std_logic;
        Error      : std_logic;
        TimeOutCnt  : natural;
    end record;
	 
    type TTXContext is record
        state       : TTXState;
        tx_data     : std_logic_vector(23 downto 0); 
        bitcount    : natural range 0 to 23; 
        strobe      : std_logic;
        data        : std_logic;
        DelayCount  : natural range 0 to 16#FFFF#;
		  Prescale	  : std_logic_vector(15 downto 0);
		  Busy : std_logic;
    end record;


    signal rtx, rtxin   : TTXContext;

    signal rRx, rRxIn   : RxContext_t;
    signal Rcnt, Rcnt_f, RcntL, RcntLL : natural range 0 to 15;
    signal Cnt  : std_logic_vector(3 downto 0);
    


    attribute syn_isclock                   : boolean;
    attribute syn_isclock of clk_rec_buf    : signal is true;



	constant TimeoutCount             : natural := 96296;

begin

    g_x: xor2 port map ( i1 => data_in, i0 => strobe_in, o=> clk_rec);
    b_c: bufg port map ( i => clk_rec, o => clk_rec_buf);

    rising_reg0: fd port map (d => data_in, c => clk_rec_buf, q => rxdata_r(13));
    falling_reg0: fd_1 port map (d => data_in, c => clk_rec_buf, q => rxdata_f(13));

    
    shift_reg : for i in 12 downto 0 generate
        rising_reg: fd_1 port map (d => rxdata_r(i+1), c => clk_rec_buf, q => rxdata_r(i));
    end generate;

    shift_regf : for i in 12 downto 1 generate
        rising_regf: fd_1 port map (d => rxdata_f(i+1), c => clk_rec_buf, q => rxdata_f(i));
    end generate;
    

    seq_a: process (clk_rec_buf, rrx)
        
    begin
        if (rrx.cntrst = '0') then
            cnt <= std_logic_vector(to_unsigned(0,4));
        elsif ( clk_rec_buf'event and clk_rec_buf = '1') then
            cnt <= std_logic_vector(to_unsigned(to_integer(unsigned(cnt)) + 1,4)); 
        end if;    
    end process;



    seq: process (clk, rstn)
    begin
        if (rstn = '0') then
           rRx.State <= stIdle;
            rRx.RxData <= (others => '0');
            rRx.TimeOutCnt <= 0;
            rRx.CntRst <= '0';
            rRx.Irq <= '0';
            rRx.Error <= '0';
            rtx.state <= stIdle;
            rtx.tx_data <= (others => '0');
            rtx.bitcount <= 0;
            rtx.data <= '0';
            rtx.strobe <= '0';
            rtx.DelayCount <= 0;
			rTx.Prescale <= (others => '0');
			rTx.Busy <= '0';
			Rcnt <= 0;
            Rcnt_f <= 0;
        elsif ( clk'event and clk = '1') then
            rrx <= rrxin;
            rtx <= rtxin;
			Rcnt_f <= RcntLL;
            Rcnt <= RcntL;   
        end if;
    end process;


  P_RXCMB: process(rRx, RxData_r, RxData_f, Rcnt, Rcnt_f,Cnt)
        variable v: RxContext_t;
    begin
        v := rRx;
        v.CntRst := '1';
        v.Irq := '0';
        v.Error := '0';
        case (rRx.State ) is
            when stIdle =>
                if ((Rcnt_f > 0) and (rRx.CntRst = '1')) then
                    v.State := stReceive;
                end if;
                v.TimeOutCnt := 0;
            when stReceive => 
                if (rRx.TimeOutCnt > TimeoutCount ) then
                    v.State := stIdle;
                    v.Error := '1';
                    v.CntRst := '0';
                else
                    v.TimeOutCnt := rRx.TimeOutCnt + 1;
                end if;
                if (Rcnt = Rcnt_f) and (Rcnt_f > 12) then
                    v.State := stIdle;
                    v.TimeOutCnt := 0;
                    v.CntRst := '0';
                    v.Irq := '1';
                    for i in 13 downto 2 loop
                        v.RxData((i - 2) * 2 +1):=  RxData_r(13 - i);
                        v.RxData((i - 2) * 2):=  RxData_f(14 - i);                     
                    end loop;
                end if;
            when others =>
                v.State := stIdle;
        end case;
        if  rRx.CntRst = '1' then
            RcntL <= to_integer(unsigned(Cnt));
            RcntLL <= Rcnt;
        else
            RcntL <= 0;
            RcntLL <= 0;
        end if;
        rRxIn <= v;
    end process;

    rx_data <= rrx.Rxdata;
    rx_irq <= rrx.irq;

    rx_error <= rrx.error;

        com_tx: process(rtx,tx_go, tx_data, tx_prescale)
        variable v: TTXContext;
    begin
        v := rtx;
        case (rtx.state ) is
            when stIdle =>
                if (tx_go = '1') then
                    v.state := stTransmit0;
                    v.tx_data := tx_data;
                    v.bitcount := 23;
                    v.Prescale := tx_prescale;
						  v.DelayCount := to_integer(unsigned(tx_prescale));
                end if;
                tx_irq <= '0';
            when stTransmit0 => 
                if rTx.DelayCount = 0 then
                    v.strobe := rtx.tx_data(rtx.bitcount) xor '1';
                    v.data := rtx.tx_data(rtx.bitcount);
                    v.bitcount :=  rtx.bitcount - 1;
                    v.state := stTransmit1;
                    v.DelayCount := to_integer(unsigned(rTx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stTransmit1 => 
                if rTx.DelayCount = 0 then
                    v.strobe := rtx.tx_data(rtx.bitcount) xor '0';
                    v.data := rtx.tx_data(rtx.bitcount);
                    if (rtx.bitcount = 0) then
                        v.state := stStop1;
                    else
                        v.bitcount :=  rtx.bitcount - 1;
                        v.state := stTransmit0;
                    end if;
                    v.DelayCount := to_integer(unsigned(Rtx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stStop1 => 
                if rTx.DelayCount = 0 then
                    v.data := '0';
                    v.strobe := '1';
                    v.state := stStop2;
                    v.DelayCount := to_integer(unsigned(Rtx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stStop2 =>
                if rTx.DelayCount = 0 then
                    v.data := '0';
                    v.strobe := '0';
                    v.state := stSilent1;
                    v.DelayCount := to_integer(unsigned(Rtx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stSilent1 =>                
                if rTx.DelayCount = 0 then
                    v.state := stSilent2;
                    v.DelayCount := to_integer(unsigned(rTx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;   
                tx_irq <= '0';
            when stSilent2 =>
                if rTx.DelayCount = 0 then
                    v.state := stSilent3;
                    v.DelayCount := to_integer(unsigned(RTx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stSilent3 =>
                if rTx.DelayCount <= 1 then
						v.state := stIdle;
                    v.DelayCount := to_integer(unsigned(RTx.prescale));
                else
                    v.DelayCount := rTx.DelayCount - 1;
                end if;
                tx_irq <= '0';
            when stIrq =>
                tx_irq <= '1';
                v.state := stIdle;
            when others =>
                v.state := stIdle;
                tx_irq <= '0';
        end case;
        rtxin <= v;
    end process;

	tx_busy <= '0' when rtx.state = stIdle else '1';

    strobe_out <= rtx.strobe;
    data_out <= rtx.data;
end architecture;