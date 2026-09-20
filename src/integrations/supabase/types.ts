export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      balance_transactions: {
        Row: {
          amount: number
          balance_after: number
          created_at: string
          created_by: string | null
          description: string
          id: string
          reference_id: string | null
          type: Database["public"]["Enums"]["ledger_type"]
          user_id: string
        }
        Insert: {
          amount: number
          balance_after: number
          created_at?: string
          created_by?: string | null
          description: string
          id?: string
          reference_id?: string | null
          type: Database["public"]["Enums"]["ledger_type"]
          user_id: string
        }
        Update: {
          amount?: number
          balance_after?: number
          created_at?: string
          created_by?: string | null
          description?: string
          id?: string
          reference_id?: string | null
          type?: Database["public"]["Enums"]["ledger_type"]
          user_id?: string
        }
        Relationships: []
      }
      pix_charges: {
        Row: {
          amount: number
          created_at: string
          credited_at: string | null
          document_suffix: string
          expires_at: string
          external_ref: string
          id: string
          payer_name: string
          provider_magic_id: string | null
          provider_updated_at: string | null
          qr_code: string | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          credited_at?: string | null
          document_suffix: string
          expires_at: string
          external_ref: string
          id?: string
          payer_name: string
          provider_magic_id?: string | null
          provider_updated_at?: string | null
          qr_code?: string | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          credited_at?: string | null
          document_suffix?: string
          expires_at?: string
          external_ref?: string
          id?: string
          payer_name?: string
          provider_magic_id?: string | null
          provider_updated_at?: string | null
          qr_code?: string | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      pix_keys: {
        Row: {
          created_at: string
          id: string
          key_value: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          key_value: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          key_value?: string
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          balance: number
          created_at: string
          demo_balance: number
          email: string | null
          id: string
          invite_code: string
          level: number
          phone: string | null
          referred_by: string | null
          reward_balance: number
        }
        Insert: {
          balance?: number
          created_at?: string
          demo_balance?: number
          email?: string | null
          id: string
          invite_code: string
          level?: number
          phone?: string | null
          referred_by?: string | null
          reward_balance?: number
        }
        Update: {
          balance?: number
          created_at?: string
          demo_balance?: number
          email?: string | null
          id?: string
          invite_code?: string
          level?: number
          phone?: string | null
          referred_by?: string | null
          reward_balance?: number
        }
        Relationships: []
      }
      recharge_requests: {
        Row: {
          amount: number
          created_at: string
          id: string
          note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["request_status"]
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          user_id?: string
        }
        Relationships: []
      }
      simpix_webhook_events: {
        Row: {
          error_message: string | null
          event_type: string
          id: string
          payload: Json
          processed: boolean
          processed_at: string | null
          received_at: string
        }
        Insert: {
          error_message?: string | null
          event_type: string
          id?: string
          payload: Json
          processed?: boolean
          processed_at?: string | null
          received_at?: string
        }
        Update: {
          error_message?: string | null
          event_type?: string
          id?: string
          payload?: Json
          processed?: boolean
          processed_at?: string | null
          received_at?: string
        }
        Relationships: []
      }
      user_roles: {
        Row: {
          id: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: string
          role: Database["public"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: string
          role?: Database["public"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: []
      }
      user_vehicles: {
        Row: {
          catalog_id: string | null
          cycle: string
          daily: string
          id: string
          image_key: string
          name: string
          plate: string
          price: string
          purchase_price: number | null
          purchased_at: string
          region: string
          return_value: string
          user_id: string
        }
        Insert: {
          catalog_id?: string | null
          cycle: string
          daily: string
          id?: string
          image_key: string
          name: string
          plate: string
          price: string
          purchase_price?: number | null
          purchased_at?: string
          region: string
          return_value: string
          user_id: string
        }
        Update: {
          catalog_id?: string | null
          cycle?: string
          daily?: string
          id?: string
          image_key?: string
          name?: string
          plate?: string
          price?: string
          purchase_price?: number | null
          purchased_at?: string
          region?: string
          return_value?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_vehicles_catalog_id_fkey"
            columns: ["catalog_id"]
            isOneToOne: false
            referencedRelation: "vehicle_catalog"
            referencedColumns: ["id"]
          },
        ]
      }
      vehicle_catalog: {
        Row: {
          active: boolean
          created_at: string
          cycle_days: number
          daily_amount: number
          id: string
          image_key: string
          name: string
          price: number
          region: string
          return_amount: number
        }
        Insert: {
          active?: boolean
          created_at?: string
          cycle_days?: number
          daily_amount: number
          id: string
          image_key: string
          name: string
          price: number
          region: string
          return_amount: number
        }
        Update: {
          active?: boolean
          created_at?: string
          cycle_days?: number
          daily_amount?: number
          id?: string
          image_key?: string
          name?: string
          price?: number
          region?: string
          return_amount?: number
        }
        Relationships: []
      }
      withdrawal_requests: {
        Row: {
          amount: number
          created_at: string
          id: string
          pix_key: string
          reviewed_at: string | null
          reviewed_by: string | null
          status: Database["public"]["Enums"]["request_status"]
          user_id: string
        }
        Insert: {
          amount: number
          created_at?: string
          id?: string
          pix_key: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          user_id: string
        }
        Update: {
          amount?: number
          created_at?: string
          id?: string
          pix_key?: string
          reviewed_at?: string | null
          reviewed_by?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      admin_adjust_balance: {
        Args: {
          _amount: number
          _reason: string
          _user_id: string
          _wallet: string
        }
        Returns: number
      }
      admin_adjust_demo_balance: {
        Args: { _amount: number; _reason: string; _user_id: string }
        Returns: number
      }
      admin_review_recharge: {
        Args: { _approve: boolean; _request_id: string }
        Returns: undefined
      }
      admin_review_withdrawal: {
        Args: { _approve: boolean; _request_id: string }
        Returns: undefined
      }
      confirm_pix_charge: {
        Args: {
          _amount: number
          _external_ref: string
          _magic_id: string
          _provider_updated_at?: string
        }
        Returns: boolean
      }
      get_admin_dashboard: { Args: never; Returns: Json }
      has_role: {
        Args: {
          _role: Database["public"]["Enums"]["app_role"]
          _user_id: string
        }
        Returns: boolean
      }
      purchase_vehicle: { Args: { _catalog_id: string }; Returns: string }
      request_demo_recharge: { Args: { _amount: number }; Returns: string }
      request_withdrawal: {
        Args: { _amount: number; _pix_key: string }
        Returns: string
      }
      update_pix_charge_status: {
        Args: {
          _external_ref: string
          _magic_id: string
          _provider_updated_at?: string
          _status: string
        }
        Returns: undefined
      }
    }
    Enums: {
      app_role: "admin" | "user"
      ledger_type:
        | "recharge"
        | "vehicle_purchase"
        | "withdrawal"
        | "admin_adjustment"
      request_status: "pending" | "approved" | "rejected"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      app_role: ["admin", "user"],
      ledger_type: [
        "recharge",
        "vehicle_purchase",
        "withdrawal",
        "admin_adjustment",
      ],
      request_status: ["pending", "approved", "rejected"],
    },
  },
} as const
