defmodule Openskill do
  @moduledoc """
    Openskill is a library for calculating skill ratings.
  """

  alias Openskill.{Environment, Util}

  @env %Environment{}

  @type mu() :: float()
  @type sigma() :: float()
  @type ordinal() :: float()
  @type mu_sigma_pair() :: {mu(), sigma()}
  @type mu_sigma_pair_with_id() :: {any, mu_sigma_pair()}

  @doc """
  Creates an initialized rating.

  ## Examples

      iex> Openskill.rating
      { 25, 8.333 }

      iex> Openskill.rating(1000, 32)
      { 1000, 32 }
  """
  @spec rating(mu() | nil, sigma() | nil) :: mu_sigma_pair()
  def rating(mu \\ nil, sigma \\ nil) do
    {mu || @env.mu, sigma || @env.sigma}
  end

  @spec ordinal(mu_sigma_pair()) :: ordinal()
  def ordinal({mu, sigma}) do
    mu - @env.z * sigma
  end

  @doc """
  Takes a list of ratings, first item is the winning team and second item is the losing team. Output is the same format as the input.
  [
    [
      {mu, sigma},
      {mu, sigma}
    ],
    [
      {mu, sigma},
      {mu, sigma}
    ]
  ]
  """
  @spec rate([[mu_sigma_pair()]], list()) :: [[mu_sigma_pair()]]
  def rate(rating_groups, options \\ []) do
    defaults = [
      weights: Util.default_weights(rating_groups),
      ranks: Util.default_ranks(rating_groups),
      model: Openskill.PlackettLuce,
      tau: @env.tau,
      prevent_sigma_increase: @env.prevent_sigma_increase
    ]

    options = Keyword.merge(defaults, options) |> Enum.into(%{})

    new_rating_groups =
      Enum.map(rating_groups, fn team ->
        Enum.map(team, fn {mu, sigma} ->
          {mu, Math.sqrt(sigma ** 2 + options.tau ** 2)}
        end)
      end)

    output = options.model.rate(new_rating_groups, options)

    if options.tau > 0 and options.prevent_sigma_increase do
      Enum.zip(rating_groups, output)
      |> Enum.map(fn {old_team, new_team} ->
        Enum.zip(old_team, new_team)
        |> Enum.map(fn {{_old_mu, old_sigma}, {new_mu, new_sigma}} ->
          {new_mu, min(old_sigma, new_sigma)}
        end)
      end)
    else
      output
    end
  end

  @doc """
  Same as rate but this time it expects each input to have an identifier as part of their tuple.

  [
    [
      {id, {mu, sigma}},
      {id, {mu, sigma}}
    ],
    [
      {id, {mu, sigma}},
      {id, {mu, sigma}}
    ]
  ]

  The result is in the same format as the input, just like `rate/2`
  [
    [
      {id, {mu, sigma}},
      {id, {mu, sigma}}
    ],
    [
      {id, {mu, sigma}},
      {id, {mu, sigma}}
    ]
  ]

  You can use the following to easily convert the results into a lookup:
    ```
    rating_groups
      |> Openskill.rate_with_ids
      |> List.flatten
      |> Map.new
    ```
  """
  @spec rate_with_ids([[mu_sigma_pair_with_id()]], list()) :: [[mu_sigma_pair_with_id()]]
  def rate_with_ids(rating_groups, options \\ []) do
    rating_groups_without_ids =
      rating_groups
      |> Enum.map(fn ratings_with_ids ->
        ratings_with_ids
        |> Enum.map(fn {_, rating} ->
          rating
        end)
      end)

    result =
      rate(rating_groups_without_ids, options)
      |> Enum.zip(rating_groups)
      |> Enum.map(fn {updated_values, original_values} ->
        original_values
        |> Enum.zip(updated_values)
        |> Enum.map(fn {{id, _}, updated_value} ->
          {id, updated_value}
        end)
      end)

    if options[:as_map] do
      result
      |> List.flatten()
      |> Map.new()
    else
      result
    end
  end

  @doc """
  Predict the win probability for each team.

  ## Examples

      iex> teams = [
      ...>   [{25, 8.333}, {30, 6.666}],
      ...>   [{27, 7.0}, {28, 5.5}]
      ...> ]
      iex> Openskill.predict_win(teams)
      [0.5, 0.5]

  In this example, since the sum of mu of each team is equal, the expectation is 50% win probability for both teams
  """
  @spec predict_win([[mu_sigma_pair()]]) :: [float()]
  def predict_win(teams) do
    team_ratings = Openskill.Util.team_rating(teams)
    n = length(teams)
    denom = n * (n - 1) / 2
    betasq = @env.beta * @env.beta

    team_ratings
    |> Enum.with_index()
    |> Enum.map(fn {{mu_a, sigma_sq_a, _team, _i}, i} ->
      sum =
        team_ratings
        |> Enum.with_index()
        |> Enum.filter(fn {_, q} -> i != q end)
        |> Enum.map(fn {{mu_b, sigma_sq_b, _team, _i}, _} ->
          # mu_a and mu_b is the sum of mu of players on that team
          # phi_major(0) will equal 50% win probability
          # So the larger team a mu is compared to team b, the higher chance of team a winning
          # If the uncertainty is increased for either team, then this will make it closer to 50% win probability
          phi_major((mu_a - mu_b) / :math.sqrt(n * betasq + sigma_sq_a + sigma_sq_b))
        end)
        |> Enum.sum()

      sum / denom
    end)
  end

  # Gives the probability that a statistic is less than Z
  # Assumes normal distribution with mean 0 and s.d. of 1
  # https://hexdocs.pm/statistics/Statistics.Distributions.Normal.html#cdf/0-examples
  # if the input is 0 then the result will be 50%
  def phi_major(input) do
    Statistics.Distributions.Normal.cdf().(input)
  end
end
