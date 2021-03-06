defmodule EventManager.Repo.Migrations.CreateAttendances do
  use Ecto.Migration

  def change do
    create table(:attendances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string
      add :attendee_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :event_id, references(:events, on_delete: :nothing, type: :binary_id)

      timestamps()
    end

    create unique_index(:attendances, [:attendee_id, :event_id])
    create unique_index(:attendances, [:email, :event_id])
  end
end
