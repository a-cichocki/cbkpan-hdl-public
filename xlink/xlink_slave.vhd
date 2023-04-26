-- Author:  Andrzej Cichocki
-- Centrum Badan Kosmicznych PAN
-- ASIM MXGS Project
-- Public domain released with master thesis 

library ieee;
    use ieee.numeric_std.all;
    use ieee.std_logic_1164.all;

library unisim;
	use unisim.vcomponents.all;


entity xlink_slave is
    generic (
        TimeoutCount             : natural := 96296
    );
    port (
    -- Group : 
        iData                    : in std_logic; -- 
        iStrobe                  : in std_logic; -- 
        iTxData                  : in std_logic_vector(23 downto 0); -- 
        iTxGo                    : in std_logic; -- 
        oData                    : out std_logic; -- 
        oRxData                  : out std_logic_vector(23 downto 0); -- 
        oRxError                 : out std_logic; -- 
        oRxIrq                   : out std_logic; -- 
        oStrobe                  : out std_logic; -- 
        oTxIrq                   : out std_logic; -- 
    -- Group : !Basic signals
        iClk                     : in std_logic; -- 
        iRst_n                   : in std_logic -- 
    );
end entity;

architecture Mixed of xlink_slave is

    signal Vcc          :   std_logic;
    signal Gnd          :   std_logic;
    signal ClkRec      :   std_logic;
    signal ClkRec_b  :   std_logic;
    signal RxData_r    :   std_logic_vector(13 downto 0);
    signal RxData_f    :   std_logic_vector(13 downto 1);
    
    type RxState_t is ( stIdle, stReceive, stError, stIrq,stResync, stSilent);
    type TxState_t is ( stIdle, stTransmit1, stTransmit0, stStop1, stStop2, stSilent1, stSilent2, StSilent3, stIrq);
    
    type RxContext_t is record
        State       : RxState_t;
        RxData     : std_logic_vector(23 downto 0); 
        CntRst      : std_logic;
        Irq         : std_logic;
        Error      : std_logic;
        TimeOutCnt  : natural;
    end record;
    
    type TxContext_t is record
        State       : TxState_t;
        TxData     : std_logic_vector(23 downto 0); 
        BitCount    : natural range 0 to 23; 
        Strobe      : std_logic;
        Data        : std_logic;
        Irq         : std_logic;
        WaitState   : std_logic;
    end record;
    
    signal rRx, rRxIn   : RxContext_t;
    signal rTx, rTxIn   : TxContext_t;
    signal Rcnt, Rcnt_f, RcntL, RcntLL : natural range 0 to 15;

    signal Cnt  : std_logic_vector(3 downto 0);
    
    attribute syn_isclock                   : boolean;
    attribute syn_isclock of ClkRec_b    : signal is true;
    attribute syn_isclock of ClkRec        : signal is true;
    
    attribute syn_keep                      : boolean;
    attribute syn_keep of ClkRec_b    : signal is true;
    attribute syn_keep of ClkRec        : signal is true;
    
    
begin
    Vcc <= '1';
    Gnd <= '0';
    I_Gate0:    xor2 port map ( i1 => iData, i0 => iStrobe, o=> ClkRec);
    I_Bufer0:   bufg port map ( i => ClkRec, o => ClkRec_b);
    
    I_FlipFlop0R : fd port map (d => iData, c => ClkRec_b, q => RxData_r(13));
    I_FlipFlop0F : fd_1 port map (d => iData, c => ClkRec_b, q => RxData_f(13));
            
    I_ShiftRegR : for i in 12 downto 0 generate
        I_FlipFlopR: fd_1 port map (d => RxData_r(i+1),  c => ClkRec_b, q => RxData_r(i));
    end generate;
    
    I_ShiftRegF : for i in 12 downto 1 generate
        I_FlipFlopF: fd_1 port map (d => RxData_f(i+1),  c => ClkRec_b, q => RxData_f(i));
    end generate;
    
	
	seq_counter: process (ClkRec_b, rRx)       
    begin
        if (rRx.CntRst = '0') then
            Cnt <= std_logic_vector(to_unsigned(0,4));
        elsif ( ClkRec_b'event and ClkRec_b = '0') then
            Cnt <= std_logic_vector(to_unsigned(to_integer(unsigned(Cnt)) + 1,4)); 
        end if;    
    end process;
	
	    
    P_SEQ: process (iClk, iRst_n)
    begin
        if (iRst_n = '0') then
            rRx.State <= stIdle;
            rRx.RxData <= (others => '0');
            rRx.TimeOutCnt <= 0;
            rRx.CntRst <= '0';
            rRx.Irq <= '0';
            rRx.Error <= '0';
            rTx.State <= stIdle;
            rTx.TxData <= (others => '0');
            rTx.BitCount <= 0;
            rTx.Data <= '0';
            rTx.Strobe <= '0';
            rTx.Irq <= '0';
            rTx.WaitState <= '0';
            Rcnt <= 0;
            Rcnt_f <= 0;
        elsif ( iClk'event and iClk = '1') then
            rRx <= rRxIn;
            rTx <= rTxIn;
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
    
    P_TXCMB: process(rTx, iTxGo, iTxData)
        variable v: TxContext_t;
    begin
        v := rTx;
        v.Irq := '0';
        case (rTx.State ) is
            when stIdle =>
                if (iTxGo = '1') then
                    v.State := stTransmit0;
                    v.TxData := iTxData;
                    v.BitCount := 23;
                    v.WaitState := '1';
                end if;
            when stTransmit0 =>                 
                v.Strobe := rTx.TxData(rTx.BitCount) xor '1';
                v.Data := rTx.TxData(rTx.BitCount);
                if rTx.WaitState = '0' then
                    v.BitCount :=  rTx.BitCount - 1;
                    v.State := stTransmit1;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;
            when stTransmit1 => 
                v.Strobe := rTx.TxData(rTx.BitCount) xor '0';
                v.Data := rTx.TxData(rTx.BitCount);
                if rTx.WaitState = '0' then
                    if (rTx.BitCount = 0) then
                        v.State := stStop1;
                    else
                        v.BitCount :=  rTx.BitCount - 1;
                        v.State := stTransmit0;
                    end if;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;                
            when stStop1 => 
                if rTx.WaitState = '0' then
                    v.State := stStop2;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;
                v.Data := '0';
                v.Strobe := '1';                
            when stStop2 =>
                if rTx.WaitState = '0' then
                    v.State := stSilent1;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;           
                v.Data := '0';
                v.Strobe := '0';
            when stSilent1 =>
                if rTx.WaitState = '0' then
                    v.State := stSilent2;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;           
            when stSilent2 =>
                if rTx.WaitState = '0' then
                    v.State := stSilent3;
                    v.WaitState := '1';
                else
                    v.WaitState := '0';
                end if;           
            when stSilent3 =>
                if rTx.WaitState = '0' then
                    v.WaitState := '1';
                    v.State := stIdle;
                    v.Irq := '1';
                else
                    v.WaitState := '0';
                end if; 
            when others =>
                v.State := stIdle;
        end case;
        rTxIn <= v;
    end process;
    
    
    oRxData     <= rRx.RxData;
    oRxIrq      <= rRx.Irq;
    oRxError    <= rRx.Error;
    
    oTxIrq      <= rTx.Irq; 
    oStrobe     <= rTx.Strobe;
    oData       <= rTx.Data;
end architecture;